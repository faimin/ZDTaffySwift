#if canImport(UIKit)
import UIKit
import ZDLayoutCore

/// A virtual view: the place a container (or any node) occupies, without adding a view to the hierarchy.
///
/// ```swift
/// let header = FlexGuide()
///
/// FlexView {
///     Column {
///         Row { avatar.size(40); title.grow(1) }.guide(header)
///         …
///     }
/// }
///
/// header.whenInstalled { guide in            // Auto Layout
///     badge.topAnchor.constraint(equalTo: guide.topAnchor).isActive = true
/// }
/// header.frame                               // or just read the frame after layout
/// ```
///
/// The host installs ``layoutGuide`` in itself during the first layout pass and pins it to the node with four
/// constant constraints, updating them (only when the frame changed) after each pass. It is removed again when the
/// description stops mentioning the guide, which also drops constraints that referred to it. A guide belongs to
/// one host at a time.
///
/// Constraints that mention ``layoutGuide`` can only be activated while it is installed. Create them in
/// ``whenInstalled(_:)``, which runs right after installation (or immediately if that already happened).
open class FlexGuide: LayoutGuide {
    private var storage: UILayoutGuide?
    private var installHandlers: [@MainActor (UILayoutGuide) -> Void] = []

    public override init() {
        super.init()
    }

    /// The `UILayoutGuide` that follows the node. Constrain other views to its anchors, but only once it is
    /// installed (see ``whenInstalled(_:)``).
    @MainActor
    public var layoutGuide: UILayoutGuide {
        if let storage { return storage }
        let created = UILayoutGuide()
        created.identifier = "FlexGuide"
        storage = created
        return created
    }

    /// Runs `handler` every time a host installs the guide, and immediately if it is installed now.
    @MainActor
    public func whenInstalled(_ handler: @escaping @MainActor (UILayoutGuide) -> Void) {
        installHandlers.append(handler)
        if layoutGuide.owningView != nil { handler(layoutGuide) }
    }

    @MainActor
    func didInstall() {
        let guide = layoutGuide
        installHandlers.forEach { $0(guide) }
    }
}
#endif
