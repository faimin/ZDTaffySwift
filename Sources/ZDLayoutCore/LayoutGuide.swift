import CoreGraphics

/// Reports where a node ended up, without being a view.
///
/// Attach one with ``LayoutComponent/guide(_:)``. After every layout pass the host calls ``resolve(_:)`` with the
/// node's frame, expressed in the host's coordinate space, so a container (`Row`, `Column`, …) can be located and
/// followed even though it has no view of its own.
open class LayoutGuide {
    /// The frame from the last layout pass; `.zero` before the first one or while the node is hidden.
    public private(set) var frame: CGRect = .zero

    public init() {}

    /// Called by the layout host. Subclasses may override to react, and must call `super`.
    open func resolve(_ frame: CGRect) {
        self.frame = frame
    }
}

extension LayoutNode {
    /// Calls `body` for this node and every descendant, parents first, pairing each with its solved layout.
    ///
    /// `result` must come from solving this node (or a tree of the same shape).
    public func forEach(solvedBy result: ResolvedLayout, _ body: (LayoutNode, ResolvedLayout) -> Void) {
        body(self, result)
        for (child, childResult) in zip(children, result.children) {
            child.forEach(solvedBy: childResult, body)
        }
    }
}

extension LayoutComponent {
    /// Tells `guide` where this node is laid out.
    public func guide(_ guide: LayoutGuide) -> LayoutNode {
        var node = layoutNode
        node.guide = guide
        return node
    }
}
