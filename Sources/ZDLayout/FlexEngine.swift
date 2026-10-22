#if canImport(UIKit)
import UIKit
import ZDLayoutCore

/// How a container reserves space for system chrome.
public enum FlexInsets: Hashable, Sendable {
    /// No padding. Right for nested containers.
    case none
    /// The view's `safeAreaInsets`. Opt in on the top-level container only.
    case safeArea
    /// The view's `directionalLayoutMargins`.
    case layoutMargins
}

/// Turns a declarative description into subviews and frames for one host view. Shared by ``FlexView`` and
/// ``FlexScrollView``.
@MainActor
final class FlexEngine {
    private var managed: [ObjectIdentifier: UIView] = [:]
    private(set) var lastRoot: LayoutNode?
    private(set) var lastResult: ResolvedLayout?

    // MARK: Building

    func environment(for host: UIView) -> LayoutEnvironment {
        let scale = host.window?.screen.scale ?? host.traitCollection.displayScale
        return LayoutEnvironment(
            direction: host.effectiveUserInterfaceLayoutDirection == .rightToLeft ? .rightToLeft : .leftToRight,
            scale: scale > 0 ? scale : 1
        )
    }

    /// The implicit root: a column that stretches its children and pads them by `insets`.
    func makeRoot(children: [LayoutNode], insets: FlexInsets, host: UIView, environment: LayoutEnvironment) -> LayoutNode {
        var style = LayoutStyle()
        style.axis = .column
        style.padding = Self.edges(for: insets, host: host, direction: environment.direction)
        let root = LayoutNode(style: style, children: children)
        // A hidden view takes no space, like `display: none`; the flag is read afresh every pass.
        return root.mapped { node in
            if let view = node.content as? UIView, view.isHidden { node.style.isHidden = true }
        }
    }

    private static func edges(for insets: FlexInsets, host: UIView, direction: LayoutDirection) -> Edges {
        switch insets {
        case .none:
            return .zero
        case .layoutMargins:
            let m = host.directionalLayoutMargins
            return Edges(top: .points(m.top), leading: .points(m.leading), bottom: .points(m.bottom), trailing: .points(m.trailing))
        case .safeArea:
            let s = host.safeAreaInsets
            let ltr = direction == .leftToRight
            return Edges(
                top: .points(s.top),
                leading: .points(ltr ? s.left : s.right),
                bottom: .points(s.bottom),
                trailing: .points(ltr ? s.right : s.left)
            )
        }
    }

    // MARK: Measuring

    func fittingSize(children: [LayoutNode], insets: FlexInsets, host: UIView, proposed: ProposedSize) -> CGSize {
        let environment = environment(for: host)
        let root = makeRoot(children: children, insets: insets, host: host, environment: environment)
        guard let result = try? LayoutSolver.solve(root, in: proposed, sizing: .fit, environment: environment) else { return .zero }
        return result.frame.size
    }

    // MARK: Laying out

    /// Mounts the views of `children` into `host` and positions them. Returns the size of the laid-out content.
    @discardableResult
    func layout(children: [LayoutNode], insets: FlexInsets, host: UIView, proposed: ProposedSize) -> CGSize {
        let environment = environment(for: host)
        let root = makeRoot(children: children, insets: insets, host: host, environment: environment)
        guard let result = try? LayoutSolver.solve(root, in: proposed, sizing: .fill, environment: environment) else {
            assertionFailure("ZDLayout: layout failed")
            return host.bounds.size
        }

        let leaves = root.leaves
        mount(views: leaves.compactMap { $0.content as? UIView }, in: host)

        let origin = host.bounds.origin
        for (node, resolved) in zip(leaves, result.leaves) {
            guard let view = node.content as? UIView, !view.isHidden else { continue }
            let frame = resolved.absoluteFrame.offsetBy(dx: origin.x, dy: origin.y)
            if view.transform == .identity {
                view.frame = frame
            } else {
                view.bounds = CGRect(origin: view.bounds.origin, size: frame.size)
                view.center = CGPoint(x: frame.midX, y: frame.midY)
            }
        }

        lastRoot = root
        lastResult = result
        return result.frame.size
    }

    /// Adds new views, removes the ones that disappeared and keeps managed views in description order.
    private func mount(views: [UIView], in host: UIView) {
        var seen = Set<ObjectIdentifier>()
        let desired = views.filter { seen.insert(ObjectIdentifier($0)).inserted }

        for (id, view) in managed where !seen.contains(id) {
            if view.superview === host { view.removeFromSuperview() }
        }
        managed = Dictionary(uniqueKeysWithValues: desired.map { (ObjectIdentifier($0), $0) })

        for view in desired where view.superview !== host {
            host.addSubview(view)
        }

        let current = host.subviews.filter { managed[ObjectIdentifier($0)] != nil }
        if current != desired {
            desired.forEach { host.bringSubviewToFront($0) }
        }
    }

    // MARK: Debugging

    var treeDescription: String {
        guard let root = lastRoot, let result = lastResult else { return "(not laid out yet)" }
        var lines: [String] = []
        describe(root, result, depth: 0, into: &lines)
        return lines.joined(separator: "\n")
    }

    private func describe(_ node: LayoutNode, _ result: ResolvedLayout, depth: Int, into lines: inout [String]) {
        let frame = result.frame
        let rect = "(\(frame.minX), \(frame.minY), \(frame.width), \(frame.height))"
        let name: String
        if let view = node.content as? UIView {
            name = String(describing: type(of: view))
        } else {
            name = node.style.display == .grid ? "Grid" : "Flex \(node.style.axis)"
        }
        lines.append(String(repeating: "  ", count: depth) + "\(name) \(rect)")
        for (child, childResult) in zip(node.children, result.children) {
            describe(child, childResult, depth: depth + 1, into: &lines)
        }
    }

    #if DEBUG
    private var overlay: CAShapeLayer?

    func updateOverlay(in host: UIView, isVisible: Bool) {
        guard isVisible, let result = lastResult else {
            overlay?.removeFromSuperlayer()
            overlay = nil
            return
        }
        let layer = overlay ?? CAShapeLayer()
        layer.fillColor = nil
        layer.strokeColor = UIColor.systemPink.withAlphaComponent(0.8).cgColor
        layer.lineWidth = 1 / max(host.traitCollection.displayScale, 1)
        let path = UIBezierPath()
        func add(_ node: ResolvedLayout) {
            path.append(UIBezierPath(rect: node.absoluteFrame.offsetBy(dx: host.bounds.origin.x, dy: host.bounds.origin.y)))
            node.children.forEach(add)
        }
        add(result)
        layer.path = path.cgPath
        layer.frame = host.bounds
        layer.zPosition = .greatestFiniteMagnitude
        if layer.superlayer !== host.layer { host.layer.addSublayer(layer) }
        overlay = layer
    }
    #endif
}

/// Maps a UIKit size to a proposal. Non-positive, non-finite and huge values (the usual way UIKit says
/// "no limit") mean unconstrained.
@MainActor
func proposal(for value: CGFloat) -> AvailableLength {
    value > 0 && value.isFinite && value < 1e8 ? .definite(value) : .maxContent
}
#endif
