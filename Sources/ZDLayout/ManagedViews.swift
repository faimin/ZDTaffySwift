#if canImport(UIKit)
import UIKit
import ZDLayoutCore

/// How a framework-created view is described: how to make it, and how to bring it up to date.
///
/// `body()` runs on every layout pass, so a description is recreated each time. The view it stands for is not: the
/// host keeps views in a cache and reuses the one with the same identity, calling ``update`` on it.
///
/// Identity is `id` when you give one, otherwise the position among the unnamed descriptions of the same type in
/// document order. Positions shift when an `if` adds or removes an earlier sibling; the reused view is then
/// re-updated and looks right, but it is a different object. Give views that carry state (an animation, a
/// text field's contents) an `id`.
final class ManagedViewSpec {
    let id: AnyHashable?
    let typeID: ObjectIdentifier
    let make: @MainActor () -> UIView
    let update: @MainActor (UIView) -> Void

    init(id: AnyHashable?, typeID: ObjectIdentifier, make: @escaping @MainActor () -> UIView, update: @escaping @MainActor (UIView) -> Void) {
        self.id = id
        self.typeID = typeID
        self.make = make
        self.update = update
    }
}

/// A leaf whose view is created and owned by the layout host.
///
/// Use it for any view type the built-in wrappers (``Label``, ``Image``, ``Box``) do not cover:
///
/// ```swift
/// Managed(make: { UISwitch() }) { $0.isOn = isOn }
/// ```
public struct Managed<V: UIView>: LayoutComponent {
    private let spec: ManagedViewSpec

    public init(
        id: AnyHashable? = nil,
        make: @escaping @MainActor () -> V,
        update: @escaping @MainActor (V) -> Void = { _ in }
    ) {
        spec = ManagedViewSpec(
            id: id,
            typeID: ObjectIdentifier(V.self),
            make: make,
            update: { view in
                if let view = view as? V { update(view) }
            }
        )
    }

    public var layoutNode: LayoutNode {
        LayoutNode(content: spec)
    }
}

// MARK: - Built-in wrappers

/// A `UILabel`. It wraps by default; give it `.shrink(1)` so it wraps or truncates next to other views.
public struct Label: LayoutComponent {
    public let layoutNode: LayoutNode

    /// - Parameters:
    ///   - lines: `0` wraps without limit; `1` truncates.
    ///   - font: Defaults to Dynamic Type `body`, which follows the user's text size setting.
    public init(
        _ text: String,
        font: UIFont = .preferredFont(forTextStyle: .body),
        color: UIColor = .label,
        lines: Int = 0,
        alignment: NSTextAlignment = .natural,
        id: AnyHashable? = nil
    ) {
        layoutNode = Managed<UILabel>(id: id, make: { UILabel() }) { label in
            if label.text != text { label.text = text }
            if label.font != font { label.font = font }
            label.adjustsFontForContentSizeCategory = true
            if label.textColor != color { label.textColor = color }
            if label.numberOfLines != lines { label.numberOfLines = lines }
            if label.textAlignment != alignment { label.textAlignment = alignment }
        }.layoutNode
    }
}

/// A `UIImageView`. Without a size it takes the image's own.
public struct Image: LayoutComponent {
    public let layoutNode: LayoutNode

    public init(
        _ image: UIImage?,
        tint: UIColor? = nil,
        contentMode: UIView.ContentMode = .scaleAspectFit,
        id: AnyHashable? = nil
    ) {
        layoutNode = Managed<UIImageView>(id: id, make: { UIImageView() }) { view in
            if view.image !== image { view.image = image }
            if let tint, view.tintColor != tint { view.tintColor = tint }
            if view.contentMode != contentMode { view.contentMode = contentMode }
        }.layoutNode
    }
}

/// A plain `UIView` with a background colour and rounded corners. It has no size of its own: use `.size(…)`,
/// `.height(…)` or `.grow(…)`.
public struct Box: LayoutComponent {
    public let layoutNode: LayoutNode

    public init(color: UIColor?, cornerRadius: CGFloat = 0, id: AnyHashable? = nil) {
        layoutNode = Managed<UIView>(id: id, make: { UIView() }) { view in
            if view.backgroundColor != color { view.backgroundColor = color }
            if view.layer.cornerRadius != cornerRadius {
                view.layer.cornerRadius = cornerRadius
                view.layer.cornerCurve = .continuous
            }
        }.layoutNode
    }
}
#endif
