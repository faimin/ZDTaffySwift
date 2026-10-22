#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
import ZDLayoutCore

/// How a container reserves space for system chrome.
public enum FlexInsets: Hashable, Sendable {
    /// No padding. Right for nested containers.
    case none
    /// The view's `safeAreaInsets` (a toolbar or title bar over the content). Opt in on the top-level container.
    case safeArea
}

/// A view that lays its subviews out with Flexbox / Grid.
///
/// Describe the content with ``body()`` (subclass) or the `content` closure; it is re-evaluated on every layout
/// pass, so it can read your state directly. Change state, then call `needsLayout = true`.
///
/// The view is flipped (its origin is the top-left corner), like the UIKit ``FlexView`` in `ZDLayout`.
///
/// Compared with the UIKit layer this one has no `FlexScrollView`, no `FlexGuide` and no asynchronous layout; put a
/// `FlexView` inside an `NSScrollView` as its document view if you need scrolling.
@MainActor
open class FlexView: NSView, LayoutMeasurable {
    public var insets: FlexInsets = .none {
        didSet {
            guard insets != oldValue else { return }
            needsLayout = true
            invalidateIntrinsicContentSize()
        }
    }

    private let contentBuilder: (@MainActor () -> [LayoutNode])?
    private var managed: [ObjectIdentifier: NSView] = [:]
    private var created: [CreatedKey: NSView] = [:]

    /// For subclasses that override ``body()``.
    public override init(frame frameRect: NSRect) {
        contentBuilder = nil
        super.init(frame: frameRect)
    }

    public init(insets: FlexInsets = .none, @LayoutBuilder content: @escaping @MainActor () -> [LayoutNode]) {
        contentBuilder = content
        self.insets = insets
        super.init(frame: .zero)
    }

    public required init?(coder: NSCoder) {
        contentBuilder = nil
        super.init(coder: coder)
    }

    open override var isFlipped: Bool { true }

    /// The description of this view's content. The default evaluates the `content` closure.
    @LayoutBuilder
    open func body() -> [LayoutNode] {
        contentBuilder?() ?? []
    }

    // MARK: Layout

    open override func layout() {
        super.layout()
        let environment = layoutEnvironment()
        let root = makeRoot(body(), environment: environment, pruneUnused: true)
        guard let result = try? LayoutSolver.solve(root, in: ProposedSize(bounds.size), sizing: .fill, environment: environment) else {
            assertionFailure("ZDLayoutAppKit: layout failed")
            return
        }

        let leaves = root.leaves
        mount(leaves.compactMap { $0.content as? NSView })
        for (node, resolved) in zip(leaves, result.leaves) {
            guard let view = node.content as? NSView, !view.isHidden else { continue }
            view.frame = resolved.absoluteFrame.offsetBy(dx: bounds.origin.x, dy: bounds.origin.y)
        }
    }

    open override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true  // the backing scale is known now
    }

    // MARK: Sizing

    /// Sizes the content within `size`. A non-positive, non-finite or huge dimension means "no limit".
    public func sizeThatFits(_ size: CGSize) -> CGSize {
        fittingSize(ProposedSize(width: proposal(for: size.width), height: proposal(for: size.height)))
    }

    open override var intrinsicContentSize: NSSize {
        fittingSize(.unconstrained)
    }

    public func layoutSize(for constraint: MeasureConstraint) -> CGSize {
        fittingSize(ProposedSize(
            width: constraint.knownWidth.map { .definite($0) } ?? constraint.availableWidth,
            height: constraint.knownHeight.map { .definite($0) } ?? constraint.availableHeight
        ))
    }

    private func fittingSize(_ proposed: ProposedSize) -> CGSize {
        let environment = layoutEnvironment()
        let root = makeRoot(body(), environment: environment, pruneUnused: false)
        return (try? LayoutSolver.solve(root, in: proposed, sizing: .fit, environment: environment))?.frame.size ?? .zero
    }

    private func proposal(for value: CGFloat) -> AvailableLength {
        value > 0 && value.isFinite && value < 1e8 ? .definite(value) : .maxContent
    }

    // MARK: Building

    private func layoutEnvironment() -> LayoutEnvironment {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        return LayoutEnvironment(
            direction: userInterfaceLayoutDirection == .rightToLeft ? .rightToLeft : .leftToRight,
            scale: scale
        )
    }

    private func makeRoot(_ children: [LayoutNode], environment: LayoutEnvironment, pruneUnused: Bool) -> LayoutNode {
        let children = resolveCreatedViews(in: children, pruneUnused: pruneUnused)
        var style = LayoutStyle()
        style.axis = .column
        if insets == .safeArea {
            let s = safeAreaInsets
            let ltr = environment.direction == .leftToRight
            style.padding = Edges(
                top: .points(s.top),
                leading: .points(ltr ? s.left : s.right),
                bottom: .points(s.bottom),
                trailing: .points(ltr ? s.right : s.left)
            )
        }
        // A hidden view takes no space; the flag is read afresh every pass.
        return LayoutNode(style: style, children: children).mapped { node in
            if let view = node.content as? NSView, view.isHidden { node.style.isHidden = true }
        }
    }

    private struct CreatedKey: Hashable {
        let identity: AnyHashable
        let type: ObjectIdentifier
    }

    private struct NamedIdentity: Hashable {
        let id: AnyHashable
    }

    /// Replaces descriptions of framework-created views with the (cached) views themselves.
    private func resolveCreatedViews(in children: [LayoutNode], pruneUnused: Bool) -> [LayoutNode] {
        var positions: [ObjectIdentifier: Int] = [:]
        var used = Set<CreatedKey>()

        let resolved = children.map { child in
            child.mapped { node in
                guard let spec = node.content as? ManagedViewSpec else { return }
                let identity: AnyHashable
                if let id = spec.id {
                    identity = AnyHashable(NamedIdentity(id: id))
                } else {
                    let position = positions[spec.typeID, default: 0]
                    positions[spec.typeID] = position + 1
                    identity = AnyHashable(position)
                }
                let key = CreatedKey(identity: identity, type: spec.typeID)
                let view = created[key] ?? spec.make()
                created[key] = view
                used.insert(key)
                spec.update(view)

                let leaf = view.layoutNode
                node = LayoutNode(style: node.style, children: [], measure: leaf.measure, content: view, guide: node.guide)
            }
        }
        if pruneUnused { created = created.filter { used.contains($0.key) } }
        return resolved
    }

    /// Adds new views, removes the ones that disappeared and keeps managed views in description order.
    private func mount(_ views: [NSView]) {
        var seen = Set<ObjectIdentifier>()
        let desired = views.filter { seen.insert(ObjectIdentifier($0)).inserted }

        for (id, view) in managed where !seen.contains(id) {
            if view.superview === self { view.removeFromSuperview() }
        }
        managed = Dictionary(uniqueKeysWithValues: desired.map { (ObjectIdentifier($0), $0) })

        for view in desired where view.superview !== self {
            addSubview(view)
        }

        let current = subviews.filter { managed[ObjectIdentifier($0)] != nil }
        if current != desired {
            let others = subviews.filter { managed[ObjectIdentifier($0)] == nil }
            subviews = others + desired
        }
    }
}
#endif
