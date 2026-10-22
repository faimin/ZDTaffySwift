import CoreGraphics
import ZDTaffy

/// What the solver tells a leaf about the space it may occupy.
public struct MeasureConstraint: Hashable, Sendable {
    /// Dimensions the parent's algorithm has already fixed (`nil` = not fixed). A size from the node's own
    /// style is *not* reported here; it appears as `.definite` in `available`.
    public var knownWidth: CGFloat?
    public var knownHeight: CGFloat?
    public var availableWidth: AvailableLength
    public var availableHeight: AvailableLength

    public init(
        knownWidth: CGFloat? = nil,
        knownHeight: CGFloat? = nil,
        availableWidth: AvailableLength = .maxContent,
        availableHeight: AvailableLength = .maxContent
    ) {
        self.knownWidth = knownWidth
        self.knownHeight = knownHeight
        self.availableWidth = availableWidth
        self.availableHeight = availableHeight
    }
}

/// The space offered along one axis.
public enum AvailableLength: Hashable, Sendable {
    case definite(CGFloat)
    /// As little as possible (a text view wraps at every opportunity).
    case minContent
    /// As much as it wants (a text view does not wrap).
    case maxContent

    /// The definite size, or `nil` when unconstrained.
    public var definiteValue: CGFloat? {
        if case .definite(let v) = self { v } else { nil }
    }
}

/// Computes the content size of a leaf. Must be a pure function of the leaf's current state and `constraint`.
public typealias LeafMeasure = (_ constraint: MeasureConstraint) -> CGSize

/// Like ``LeafMeasure`` but may suspend, for content measured on another actor or from data that is still loading.
/// Only ``LayoutSolver/solveAsync(_:in:sizing:environment:isolation:)`` uses it. The same purity rule applies, and
/// more strongly: the solver asks again whenever the layout changes the question, so answer from state, not from
/// a counter or a clock.
public typealias AsyncLeafMeasure = (_ constraint: MeasureConstraint) async -> CGSize

/// A node of the layout tree: a style, children, and (for leaves) a way to measure content.
public struct LayoutNode {
    public var style: LayoutStyle
    public var children: [LayoutNode]
    public var measure: LeafMeasure?
    /// Preferred over ``measure`` by the asynchronous solver.
    public var asyncMeasure: AsyncLeafMeasure?
    /// An object the caller associates with the node (a platform view, say). The solver never looks at it.
    public var content: AnyObject?
    /// Told where the node ends up. The solver never looks at it; the host does.
    public var guide: LayoutGuide?

    public init(
        style: LayoutStyle = LayoutStyle(),
        children: [LayoutNode] = [],
        measure: LeafMeasure? = nil,
        asyncMeasure: AsyncLeafMeasure? = nil,
        content: AnyObject? = nil,
        guide: LayoutGuide? = nil
    ) {
        self.style = style
        self.children = children
        self.measure = measure
        self.asyncMeasure = asyncMeasure
        self.content = content
        self.guide = guide
    }

    /// The leaves of this subtree in depth-first order, matching `ResolvedLayout.leaves` element for element.
    public var leaves: [LayoutNode] {
        children.isEmpty ? [self] : children.flatMap(\.leaves)
    }

    /// Number of leaves in this subtree.
    public var leafCount: Int { leaves.count }

    /// Returns a copy with `change` applied to every node of the subtree, parents first.
    public func mapped(_ change: (inout LayoutNode) -> Void) -> LayoutNode {
        var node = self
        change(&node)
        node.children = node.children.map { $0.mapped(change) }
        return node
    }
}

/// Anything that can be placed in a ``LayoutBuilder`` block.
public protocol LayoutComponent {
    var layoutNode: LayoutNode { get }
}

extension LayoutNode: LayoutComponent {
    public var layoutNode: LayoutNode { self }
}

@resultBuilder
public enum LayoutBuilder {
    public static func buildExpression(_ component: some LayoutComponent) -> [LayoutNode] {
        [component.layoutNode]
    }

    public static func buildExpression(_ nodes: [LayoutNode]) -> [LayoutNode] { nodes }

    public static func buildBlock(_ parts: [LayoutNode]...) -> [LayoutNode] { parts.flatMap { $0 } }

    public static func buildOptional(_ part: [LayoutNode]?) -> [LayoutNode] { part ?? [] }

    public static func buildEither(first part: [LayoutNode]) -> [LayoutNode] { part }

    public static func buildEither(second part: [LayoutNode]) -> [LayoutNode] { part }

    public static func buildArray(_ parts: [[LayoutNode]]) -> [LayoutNode] { parts.flatMap { $0 } }

    public static func buildLimitedAvailability(_ part: [LayoutNode]) -> [LayoutNode] { part }
}

// MARK: - Containers

/// A general flex container.
public struct Flex: LayoutComponent {
    public let layoutNode: LayoutNode

    public init(
        _ axis: FlexAxis,
        gap: Length = 0,
        alignItems: ItemAlignment? = nil,
        justifyContent: ContentDistribution? = nil,
        wraps: Bool = false,
        @LayoutBuilder content: () -> [LayoutNode]
    ) {
        var style = LayoutStyle()
        style.axis = axis
        style.rowGap = gap
        style.columnGap = gap
        style.alignItems = alignItems
        style.justifyContent = justifyContent
        style.wraps = wraps
        layoutNode = LayoutNode(style: style, children: content())
    }
}

/// Children from leading to trailing.
public struct Row: LayoutComponent {
    public let layoutNode: LayoutNode

    public init(
        gap: Length = 0,
        alignItems: ItemAlignment? = nil,
        justifyContent: ContentDistribution? = nil,
        wraps: Bool = false,
        @LayoutBuilder content: () -> [LayoutNode]
    ) {
        layoutNode = Flex(.row, gap: gap, alignItems: alignItems, justifyContent: justifyContent, wraps: wraps, content: content).layoutNode
    }
}

/// Children from top to bottom.
public struct Column: LayoutComponent {
    public let layoutNode: LayoutNode

    public init(
        gap: Length = 0,
        alignItems: ItemAlignment? = nil,
        justifyContent: ContentDistribution? = nil,
        wraps: Bool = false,
        @LayoutBuilder content: () -> [LayoutNode]
    ) {
        layoutNode = Flex(.column, gap: gap, alignItems: alignItems, justifyContent: justifyContent, wraps: wraps, content: content).layoutNode
    }
}

/// A CSS grid container. Place items with ``LayoutComponent/gridColumn(_:)`` / ``LayoutComponent/gridRow(_:)``.
public struct Grid: LayoutComponent {
    public let layoutNode: LayoutNode

    public init(
        columns: [GridTrack],
        rows: [GridTrack] = [],
        autoColumns: [GridTrack] = [],
        autoRows: [GridTrack] = [],
        autoFlow: GridAutoFlow = .row,
        gap: Length = 0,
        @LayoutBuilder content: () -> [LayoutNode]
    ) {
        var style = LayoutStyle()
        style.display = .grid
        style.columns = columns
        style.rows = rows
        style.autoColumns = autoColumns
        style.autoRows = autoRows
        style.autoFlow = autoFlow
        style.rowGap = gap
        style.columnGap = gap
        layoutNode = LayoutNode(style: style, children: content())
    }
}

/// Empty space that grows to fill what is left over.
public struct Spacer: LayoutComponent {
    public let layoutNode: LayoutNode

    public init(minLength: Length = 0) {
        var style = LayoutStyle()
        style.grow = 1
        style.basis = minLength
        layoutNode = LayoutNode(style: style)
    }
}

/// A node without children. With `measure` its size comes from the content; without it, from its style.
public struct Leaf: LayoutComponent {
    public let layoutNode: LayoutNode

    public init(measure: LeafMeasure? = nil) {
        layoutNode = LayoutNode(measure: measure)
    }

    /// A leaf measured asynchronously. Solving it with the synchronous ``LayoutSolver/solve(_:in:sizing:environment:)``
    /// gives it no content size.
    public init(asyncMeasure: @escaping AsyncLeafMeasure) {
        layoutNode = LayoutNode(asyncMeasure: asyncMeasure)
    }
}

// MARK: - Modifiers

extension LayoutComponent {
    /// Returns a copy of this node with `change` applied to its style.
    public func styled(_ change: (inout LayoutStyle) -> Void) -> LayoutNode {
        var node = layoutNode
        change(&node.style)
        return node
    }

    public func width(_ value: Length) -> LayoutNode { styled { $0.width = value } }
    public func height(_ value: Length) -> LayoutNode { styled { $0.height = value } }
    public func size(_ width: Length, _ height: Length) -> LayoutNode {
        styled { $0.width = width; $0.height = height }
    }
    public func size(_ side: Length) -> LayoutNode { size(side, side) }
    public func minSize(width: Length = .auto, height: Length = .auto) -> LayoutNode {
        styled { $0.minWidth = width; $0.minHeight = height }
    }
    public func maxSize(width: Length = .auto, height: Length = .auto) -> LayoutNode {
        styled { $0.maxWidth = width; $0.maxHeight = height }
    }
    public func aspectRatio(_ ratio: CGFloat) -> LayoutNode { styled { $0.aspectRatio = ratio } }

    public func grow(_ factor: CGFloat = 1) -> LayoutNode { styled { $0.grow = factor } }
    public func shrink(_ factor: CGFloat) -> LayoutNode { styled { $0.shrink = factor } }
    public func basis(_ value: Length) -> LayoutNode { styled { $0.basis = value } }
    public func alignSelf(_ alignment: ItemAlignment) -> LayoutNode { styled { $0.alignSelf = alignment } }

    public func margin(_ edges: Edges) -> LayoutNode { styled { $0.margin = edges } }
    public func margin(_ all: Length) -> LayoutNode { margin(Edges(all)) }
    public func margin(horizontal: Length = 0, vertical: Length = 0) -> LayoutNode {
        margin(Edges(horizontal: horizontal, vertical: vertical))
    }
    public func padding(_ edges: Edges) -> LayoutNode { styled { $0.padding = edges } }
    public func padding(_ all: Length) -> LayoutNode { padding(Edges(all)) }
    public func padding(horizontal: Length = 0, vertical: Length = 0) -> LayoutNode {
        padding(Edges(horizontal: horizontal, vertical: vertical))
    }
    public func border(_ width: Length) -> LayoutNode { styled { $0.border = Edges(width) } }

    /// Takes the node out of the flow and pins it relative to its parent.
    public func absolute(inset: Edges = .auto) -> LayoutNode {
        styled { $0.position = .absolute; $0.inset = inset }
    }
    /// Nudges a node by `inset` without removing it from the flow.
    public func offset(_ inset: Edges) -> LayoutNode {
        styled { $0.position = .relative; $0.inset = inset }
    }

    /// A hidden node takes no space (like `display: none`).
    public func hidden(_ isHidden: Bool = true) -> LayoutNode { styled { $0.isHidden = isHidden } }

    public func gridColumn(_ placement: GridItemPlacement) -> LayoutNode { styled { $0.gridColumn = placement } }
    public func gridRow(_ placement: GridItemPlacement) -> LayoutNode { styled { $0.gridRow = placement } }
    public func gridColumn(_ line: Int, span: Int = 1) -> LayoutNode { gridColumn(.line(line, span: span)) }
    public func gridRow(_ line: Int, span: Int = 1) -> LayoutNode { gridRow(.line(line, span: span)) }

    /// Full access to the underlying `ZDTaffy.Style` for anything the modifiers do not cover.
    public func custom(_ change: @escaping (inout Style) -> Void) -> LayoutNode {
        styled { $0.custom = change }
    }
}

// MARK: - CGFloat conveniences

// Number literals already become a ``Length``. These let `CGFloat` variables (the usual UIKit currency) be passed
// directly. They are disfavoured so that a literal such as `40` keeps resolving to the ``Length`` overloads.
extension LayoutComponent {
    @_disfavoredOverload public func width(_ points: CGFloat) -> LayoutNode { width(.points(points)) }
    @_disfavoredOverload public func height(_ points: CGFloat) -> LayoutNode { height(.points(points)) }
    @_disfavoredOverload public func size(_ width: CGFloat, _ height: CGFloat) -> LayoutNode {
        size(.points(width), .points(height))
    }
    @_disfavoredOverload public func size(_ side: CGFloat) -> LayoutNode { size(.points(side)) }
    @_disfavoredOverload public func basis(_ points: CGFloat) -> LayoutNode { basis(.points(points)) }
    @_disfavoredOverload public func padding(_ all: CGFloat) -> LayoutNode { padding(.points(all)) }
    @_disfavoredOverload public func padding(horizontal: CGFloat = 0, vertical: CGFloat = 0) -> LayoutNode {
        padding(horizontal: .points(horizontal), vertical: .points(vertical))
    }
    @_disfavoredOverload public func margin(_ all: CGFloat) -> LayoutNode { margin(.points(all)) }
    @_disfavoredOverload public func margin(horizontal: CGFloat = 0, vertical: CGFloat = 0) -> LayoutNode {
        margin(horizontal: .points(horizontal), vertical: .points(vertical))
    }
}
