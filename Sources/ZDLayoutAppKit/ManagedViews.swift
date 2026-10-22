#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
import ZDLayoutCore

/// How a framework-created view is described. See ``ZDLayout``'s `Managed`: the host caches the view behind it by
/// `id`, or else by position among un-named descriptions of the same type, and calls ``update`` every pass.
final class ManagedViewSpec {
    let id: AnyHashable?
    let typeID: ObjectIdentifier
    let make: @MainActor () -> NSView
    let update: @MainActor (NSView) -> Void

    init(id: AnyHashable?, typeID: ObjectIdentifier, make: @escaping @MainActor () -> NSView, update: @escaping @MainActor (NSView) -> Void) {
        self.id = id
        self.typeID = typeID
        self.make = make
        self.update = update
    }
}

/// A leaf whose view is created and owned by the layout host.
///
/// ```swift
/// Managed<NSSwitch>(id: "enabled", make: { NSSwitch() }) { $0.state = isOn ? .on : .off }
/// ```
public struct Managed<V: NSView>: LayoutComponent {
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

    public var layoutNode: LayoutNode { LayoutNode(content: spec) }
}

/// A non-editable `NSTextField`. It wraps by default; give it `.shrink(1)` to wrap or truncate beside other views.
public struct Label: LayoutComponent {
    public let layoutNode: LayoutNode

    @MainActor
    public init(
        _ text: String,
        font: NSFont = .systemFont(ofSize: NSFont.systemFontSize),
        color: NSColor = .labelColor,
        lines: Int = 0,
        alignment: NSTextAlignment = .natural,
        id: AnyHashable? = nil
    ) {
        layoutNode = Managed<NSTextField>(id: id, make: {
            let field = NSTextField(wrappingLabelWithString: "")
            field.isSelectable = false
            return field
        }) { field in
            if field.stringValue != text { field.stringValue = text }
            if field.font != font { field.font = font }
            if field.textColor != color { field.textColor = color }
            if field.maximumNumberOfLines != lines { field.maximumNumberOfLines = lines }
            if field.alignment != alignment { field.alignment = alignment }
            field.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        }.layoutNode
    }
}

/// An `NSImageView`. Without a size it takes the image's own.
public struct Image: LayoutComponent {
    public let layoutNode: LayoutNode

    @MainActor
    public init(_ image: NSImage?, tint: NSColor? = nil, scaling: NSImageScaling = .scaleProportionallyUpOrDown, id: AnyHashable? = nil) {
        layoutNode = Managed<NSImageView>(id: id, make: { NSImageView() }) { view in
            if view.image !== image { view.image = image }
            if view.contentTintColor != tint { view.contentTintColor = tint }
            if view.imageScaling != scaling { view.imageScaling = scaling }
        }.layoutNode
    }
}

/// A plain `NSView` with a background colour and rounded corners. It has no size of its own: use `.size(…)`,
/// `.height(…)` or `.grow(…)`.
public struct Box: LayoutComponent {
    public let layoutNode: LayoutNode

    @MainActor
    public init(color: NSColor?, cornerRadius: CGFloat = 0, id: AnyHashable? = nil) {
        layoutNode = Managed<NSView>(id: id, make: {
            let view = NSView()
            view.wantsLayer = true
            return view
        }) { view in
            view.layer?.backgroundColor = color?.cgColor
            view.layer?.cornerRadius = cornerRadius
            view.layer?.cornerCurve = .continuous
        }.layoutNode
    }
}
#endif
