#if canImport(SwiftUI)
import SwiftUI
import ZDLayoutCore

/// A SwiftUI `Layout` that arranges its children with Flexbox or CSS Grid, using the same engine as ``FlexView``.
///
/// Use ``FlexStack`` rather than this directly: it also reads the display scale from the environment, which a
/// `Layout` cannot do on its own.
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
public struct FlexLayout: Layout {
    /// `Layout` is `Sendable`, and `LayoutStyle` (which can hold a closure) is not, so keep plain values.
    private struct Container: Sendable {
        var display: DisplayMode = .flex
        var axis: FlexAxis = .row
        var gap: CGFloat = 0
        var alignItems: ItemAlignment?
        var justifyContent: ContentDistribution?
        var wraps = false
        var padding: Edges = .zero
        var columns: [GridTrack] = []
        var rows: [GridTrack] = []
        var autoColumns: [GridTrack] = []
        var autoRows: [GridTrack] = []
        var autoFlow: GridAutoFlow = .row

        var style: LayoutStyle {
            var style = LayoutStyle()
            style.display = display
            style.axis = axis
            style.rowGap = .points(gap)
            style.columnGap = .points(gap)
            style.alignItems = alignItems
            style.justifyContent = justifyContent
            style.wraps = wraps
            style.padding = padding
            style.columns = columns
            style.rows = rows
            style.autoColumns = autoColumns
            style.autoRows = autoRows
            style.autoFlow = autoFlow
            return style
        }
    }

    private var container: Container

    /// SwiftUI mirrors a custom `Layout`'s output for right-to-left itself (an `HStack` is no different), so the
    /// solver always works left to right; solving a mirrored layout as well would flip it back.
    private var environment: LayoutEnvironment { LayoutEnvironment(direction: .leftToRight, scale: scale) }
    /// Points are snapped to multiples of `1 / scale`.
    private var scale: CGFloat

    /// A flex container.
    public init(
        _ axis: FlexAxis = .row,
        gap: CGFloat = 0,
        alignItems: ItemAlignment? = nil,
        justifyContent: ContentDistribution? = nil,
        wraps: Bool = false,
        padding: Edges = .zero,
        scale: CGFloat = 1
    ) {
        container = Container(
            axis: axis, gap: gap, alignItems: alignItems, justifyContent: justifyContent, wraps: wraps, padding: padding
        )
        self.scale = scale
    }

    /// A CSS grid container.
    public init(
        columns: [GridTrack],
        rows: [GridTrack] = [],
        autoColumns: [GridTrack] = [],
        autoRows: [GridTrack] = [],
        autoFlow: GridAutoFlow = .row,
        gap: CGFloat = 0,
        padding: Edges = .zero,
        scale: CGFloat = 1
    ) {
        container = Container(
            display: .grid, gap: gap, padding: padding,
            columns: columns, rows: rows, autoColumns: autoColumns, autoRows: autoRows, autoFlow: autoFlow
        )
        self.scale = scale
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let proposed = ProposedSize(width: Self.available(proposal.width), height: Self.available(proposal.height))
        guard var size = (try? LayoutSolver.solve(makeTree(subviews), in: proposed, sizing: .fit, environment: environment))?.frame.size else {
            return .zero
        }
        // A SwiftUI container decides its own size. Like an `HStack` holding a `Spacer`, one with flexible
        // content takes everything it is offered along the axis that content flexes on.
        let flexible = flexibleAxes(subviews)
        if flexible.horizontal, let width = proposal.width, width.isFinite { size.width = max(size.width, width) }
        if flexible.vertical, let height = proposal.height, height.isFinite { size.height = max(size.height, height) }
        return size
    }

    private func flexibleAxes(_ subviews: Subviews) -> (horizontal: Bool, vertical: Bool) {
        if container.display == .grid {
            return (
                (container.columns + container.autoColumns).contains(where: \.hasFraction),
                (container.rows + container.autoRows).contains(where: \.hasFraction)
            )
        }
        let growers = subviews.contains { $0[ItemStyleKey.self].grow > 0 && !$0[ItemStyleKey.self].isHidden }
        switch container.axis {
        case .row, .rowReverse: return (growers, false)
        case .column, .columnReverse: return (false, growers)
        }
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty,
              let result = try? LayoutSolver.solve(
                makeTree(subviews),
                in: ProposedSize(bounds.size),
                sizing: .fill,
                environment: environment
              ) else { return }

        for (subview, child) in zip(subviews, result.children) {
            guard !subview[ItemStyleKey.self].isHidden else { continue }
            subview.place(
                at: CGPoint(x: bounds.minX + child.frame.minX, y: bounds.minY + child.frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(child.frame.size)
            )
        }
    }

    // MARK: Building the tree

    private func makeTree(_ subviews: Subviews) -> LayoutNode {
        let children = subviews.map { subview -> LayoutNode in
            var style = LayoutStyle()
            subview[ItemStyleKey.self].apply(to: &style)
            return LayoutNode(style: style, measure: { constraint in
                subview.sizeThatFits(Self.proposal(for: constraint))
            })
        }
        return LayoutNode(style: container.style, children: children)
    }

    /// SwiftUI's vocabulary: `nil` is the ideal size, `0` the smallest.
    private static func proposal(for constraint: MeasureConstraint) -> ProposedViewSize {
        func value(known: CGFloat?, available: AvailableLength) -> CGFloat? {
            if let known { return known }
            switch available {
            case .definite(let v): return v
            case .minContent: return 0
            case .maxContent: return nil
            }
        }
        return ProposedViewSize(
            width: value(known: constraint.knownWidth, available: constraint.availableWidth),
            height: value(known: constraint.knownHeight, available: constraint.availableHeight)
        )
    }

    private static func available(_ value: CGFloat?) -> AvailableLength {
        guard let value else { return .maxContent }
        if value == 0 { return .minContent }
        return value.isFinite ? .definite(value) : .maxContent
    }
}

/// A container view that lays its children out with ``FlexLayout``, honouring the environment's display scale.
/// Right-to-left is handled by SwiftUI itself: `leading` / `trailing` edges and the order of a row mirror
/// automatically.
///
/// ```swift
/// FlexStack(.row, gap: 12, alignItems: .center) {
///     Circle().frame(width: 40, height: 40)
///     Text("A title that wraps when it has to").flexItem(grow: 1, shrink: 1)
///     Text("12m").foregroundStyle(.secondary)
/// }
/// ```
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
public struct FlexStack<Content: View>: View {
    @Environment(\.displayScale) private var displayScale

    private let make: (CGFloat) -> FlexLayout
    private let content: Content

    public init(
        _ axis: FlexAxis = .row,
        gap: CGFloat = 0,
        alignItems: ItemAlignment? = nil,
        justifyContent: ContentDistribution? = nil,
        wraps: Bool = false,
        padding: Edges = .zero,
        @ViewBuilder content: () -> Content
    ) {
        make = { FlexLayout(axis, gap: gap, alignItems: alignItems, justifyContent: justifyContent, wraps: wraps, padding: padding, scale: $0) }
        self.content = content()
    }

    public init(
        columns: [GridTrack],
        rows: [GridTrack] = [],
        autoColumns: [GridTrack] = [],
        autoRows: [GridTrack] = [],
        autoFlow: GridAutoFlow = .row,
        gap: CGFloat = 0,
        padding: Edges = .zero,
        @ViewBuilder content: () -> Content
    ) {
        make = {
            FlexLayout(columns: columns, rows: rows, autoColumns: autoColumns, autoRows: autoRows, autoFlow: autoFlow, gap: gap, padding: padding, scale: $0)
        }
        self.content = content()
    }

    public var body: some View {
        let layout = make(displayScale)
        return layout { content }
    }
}
#endif
