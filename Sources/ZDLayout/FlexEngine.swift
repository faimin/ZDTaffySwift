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
    private var created: [CreatedKey: UIView] = [:]
    private(set) var lastRoot: LayoutNode?
    private(set) var lastResult: ResolvedLayout?

    // MARK: Building

    func environment(for host: UIView) -> LayoutEnvironment {
        let scale = host.window?.screen.scale ?? host.traitCollection.displayScale
        return LayoutEnvironment(direction: direction(of: host), scale: scale > 0 ? scale : 1)
    }

    /// The nearest view that forces a direction (the host itself, or an ancestor) decides. `UIView` does not pass
    /// a forced `semanticContentAttribute` down to views created later, such as cells, so walk up to find it;
    /// with none, the system's own resolution applies.
    private func direction(of host: UIView) -> FlowDirection {
        var view: UIView? = host
        while let current = view {
            switch current.semanticContentAttribute {
            case .forceLeftToRight: return .leftToRight
            case .forceRightToLeft: return .rightToLeft
            default: view = current.superview
            }
        }
        return host.effectiveUserInterfaceLayoutDirection == .rightToLeft ? .rightToLeft : .leftToRight
    }

    private struct CreatedKey: Hashable {
        let identity: AnyHashable
        let type: ObjectIdentifier
    }

    /// Replaces descriptions of framework-created views with the views themselves, reusing cached ones.
    /// `pruneUnused` drops cached views the description no longer mentions (only a real layout pass may do that).
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

                // Keep the style the modifiers set; take measuring and the view from a regular view leaf.
                let leaf = view.layoutNode
                node = LayoutNode(style: node.style, children: [], measure: leaf.measure, content: view, guide: node.guide)
            }
        }
        if pruneUnused { created = created.filter { used.contains($0.key) } }
        return resolved
    }

    private struct NamedIdentity: Hashable {
        let id: AnyHashable
    }

    /// The implicit root: a column that stretches its children and pads them by `insets`.
    func makeRoot(children: [LayoutNode], insets: FlexInsets, host: UIView, environment: LayoutEnvironment, pruneUnused: Bool = false) -> LayoutNode {
        let children = resolveCreatedViews(in: children, pruneUnused: pruneUnused)
        var style = LayoutStyle()
        style.axis = .column
        style.padding = Self.edges(for: insets, host: host, direction: environment.direction)
        let root = LayoutNode(style: style, children: children)
        // A hidden view takes no space, like `display: none`; the flag is read afresh every pass.
        return root.mapped { node in
            if let view = node.content as? UIView, view.isHidden { node.style.isHidden = true }
        }
    }

    private static func edges(for insets: FlexInsets, host: UIView, direction: FlowDirection) -> Edges {
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

    /// Mounts the views of `children` into `host` and positions them, with the content's top-left corner at
    /// `origin` in the host's coordinate space. Returns the size of the laid-out content.
    ///
    /// A plain view lays out into its visible area, so its origin is `bounds.origin`. A scroll view's content
    /// starts at zero however far it has been scrolled.
    @discardableResult
    func layout(children: [LayoutNode], insets: FlexInsets, host: UIView, origin: CGPoint, proposed: ProposedSize) -> CGSize {
        let environment = environment(for: host)
        let root = makeRoot(children: children, insets: insets, host: host, environment: environment, pruneUnused: true)
        guard let result = try? LayoutSolver.solve(root, in: proposed, sizing: .fill, environment: environment) else {
            assertionFailure("ZDLayout: layout failed")
            return host.bounds.size
        }
        return apply(root: root, result: result, host: host, origin: origin)
    }

    /// Like ``layout(children:insets:host:origin:proposed:)``, but leaves that measure asynchronously are awaited,
    /// so the main actor is free while they work. Everything that touches views still happens on the main actor.
    @discardableResult
    func layoutAsync(children: [LayoutNode], insets: FlexInsets, host: UIView, origin: CGPoint, proposed: ProposedSize) async -> CGSize {
        let environment = environment(for: host)
        let root = makeRoot(children: children, insets: insets, host: host, environment: environment, pruneUnused: true)
        guard let result = try? await LayoutSolver.solveAsync(root, in: proposed, sizing: .fill, environment: environment) else {
            assertionFailure("ZDLayout: layout failed")
            return host.bounds.size
        }
        return apply(root: root, result: result, host: host, origin: origin)
    }

    func fittingSizeAsync(children: [LayoutNode], insets: FlexInsets, host: UIView, proposed: ProposedSize) async -> CGSize {
        let environment = environment(for: host)
        let root = makeRoot(children: children, insets: insets, host: host, environment: environment)
        guard let result = try? await LayoutSolver.solveAsync(root, in: proposed, sizing: .fit, environment: environment) else { return .zero }
        return result.frame.size
    }

    /// Puts a solved layout on screen: mounts views, sets frames, updates guides.
    private func apply(root: LayoutNode, result: ResolvedLayout, host: UIView, origin: CGPoint) -> CGSize {
        let leaves = root.leaves
        mount(views: leaves.compactMap { $0.content as? UIView }, in: host)

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

        updateGuides(root: root, result: result, origin: origin, host: host)

        lastRoot = root
        lastResult = result
        return result.frame.size
    }

    // MARK: Guides

    private final class InstalledGuide {
        let guide: FlexGuide
        let left: NSLayoutConstraint
        let top: NSLayoutConstraint
        let width: NSLayoutConstraint
        let height: NSLayoutConstraint

        @MainActor
        init(guide: FlexGuide, origin: UIView) {
            self.guide = guide
            let layoutGuide = guide.layoutGuide
            // Physical anchors, because frames are physical: they must not flip with the layout direction.
            left = layoutGuide.leftAnchor.constraint(equalTo: origin.leftAnchor)
            top = layoutGuide.topAnchor.constraint(equalTo: origin.topAnchor)
            width = layoutGuide.widthAnchor.constraint(equalToConstant: 0)
            height = layoutGuide.heightAnchor.constraint(equalToConstant: 0)
        }

        @MainActor
        func apply(_ frame: CGRect, origin: CGPoint) {
            // Changing a constraint asks UIKit for another layout pass, so leave unchanged ones alone.
            func set(_ constraint: NSLayoutConstraint, _ value: CGFloat) {
                if constraint.constant != value { constraint.constant = value }
            }
            set(left, frame.minX - origin.x)
            set(top, frame.minY - origin.y)
            set(width, frame.width)
            set(height, frame.height)
        }
    }

    private var installedGuides: [ObjectIdentifier: InstalledGuide] = [:]
    private var scrollOrigin: UIView?

    /// The view guides are measured from. For a plain host that is the host itself. A scroll view's own edges (and
    /// its `contentLayoutGuide`) move with `contentOffset` in Auto Layout, so a zero-size sibling parked at the
    /// content origin stands in for it: sibling-to-sibling constraints are not affected by the offset.
    private func guideOrigin(in host: UIView) -> UIView {
        guard let scroll = host as? UIScrollView else { return host }
        if let scrollOrigin { return scrollOrigin }
        let proxy = UIView(frame: .zero)
        proxy.isUserInteractionEnabled = false
        proxy.isHidden = true
        scroll.insertSubview(proxy, at: 0)
        scrollOrigin = proxy
        return proxy
    }

    /// Tells every guide in the description where its node landed, and keeps each ``FlexGuide``'s `UILayoutGuide`
    /// installed in `host` and pinned to that frame.
    private func updateGuides(root: LayoutNode, result: ResolvedLayout, origin: CGPoint, host: UIView) {
        var seen = Set<ObjectIdentifier>()
        root.forEach(solvedBy: result) { node, resolved in
            guard let guide = node.guide else { return }
            let frame = resolved.absoluteFrame.offsetBy(dx: origin.x, dy: origin.y)
            guide.resolve(frame)

            guard let flexGuide = guide as? FlexGuide else { return }
            let id = ObjectIdentifier(flexGuide)
            seen.insert(id)
            let installed: InstalledGuide
            if let existing = installedGuides[id] {
                installed = existing
            } else {
                flexGuide.layoutGuide.owningView?.removeLayoutGuide(flexGuide.layoutGuide)
                host.addLayoutGuide(flexGuide.layoutGuide)
                installed = InstalledGuide(guide: flexGuide, origin: guideOrigin(in: host))
                NSLayoutConstraint.activate([installed.left, installed.top, installed.width, installed.height])
                installedGuides[id] = installed
                installed.apply(frame, origin: origin)
                flexGuide.didInstall()
            }
            installed.apply(frame, origin: origin)
        }

        for (id, installed) in installedGuides where !seen.contains(id) {
            NSLayoutConstraint.deactivate([installed.left, installed.top, installed.width, installed.height])
            host.removeLayoutGuide(installed.guide.layoutGuide)
            installed.guide.resolve(.zero)
            installedGuides[id] = nil
        }
        if installedGuides.isEmpty, let proxy = scrollOrigin {
            proxy.removeFromSuperview()
            scrollOrigin = nil
        }
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
        layer.zPosition = 10_000
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
