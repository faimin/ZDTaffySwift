#if canImport(UIKit)
import CoreText
import UIKit
import ZDLayoutCore

// CALayers as leaves. A layer is lighter than a view (no responder chain, no autoresizing, no trait handling), which
// matters for gradients, shapes and text that only ever draw. Layers and views mix freely in one description and
// stack in the order they are written.

/// A layer that knows how big its content is.
///
/// A plain `CALayer` has no intrinsic size: give it one with `.size(…)`. `CALayer.preferredFrameSize()` is not used
/// because for most layers it just echoes the current `bounds` (and `CAShapeLayer` reports zero), so it cannot tell
/// "I am this big" from "I have not been laid out".
@MainActor
public protocol LayerMeasurable: CALayer {
    /// The content size for `constraint`. Must be a pure function of the layer's current state.
    func layoutSize(for constraint: MeasureConstraint) -> CGSize
}

// Any `CALayer` can be placed in a ``LayoutBuilder`` block and takes every modifier, e.g. `gradient.size(100, 4)`.
// The conformance is nonisolated for the same reason as `UIView`'s: `LayoutComponent` lives in a UI-agnostic module.
extension CALayer: LayoutComponent {
    nonisolated public var layoutNode: LayoutNode {
        // Unlike `UIView`, `CALayer` is not main-actor isolated, so `self` has to be carried in explicitly.
        let layer = MainThreadBox(self)
        return MainActor.assumeIsolated { MainThreadBox(layer.value.makeLeafNode()) }.value
    }
}

extension CALayer {
    @MainActor
    fileprivate func makeLeafNode() -> LayoutNode {
        var style = LayoutStyle()
        style.isHidden = isHidden
        var measure: LeafMeasure?
        if let measurable = self as? LayerMeasurable {
            measure = { constraint in MainActor.assumeIsolated { measurable.layoutSize(for: constraint) } }
        }
        return LayoutNode(style: style, measure: measure, content: self)
    }
}

// MARK: - Layers the host creates

/// How a framework-created layer is described. Same identity rules as ``Managed``: the host caches the layer behind it
/// by `id`, or else by position among un-named descriptions of the same type, and calls ``update`` every pass.
final class ManagedLayerSpec {
    let id: AnyHashable?
    let typeID: ObjectIdentifier
    let make: @MainActor () -> CALayer
    let update: @MainActor (CALayer) -> Void

    init(id: AnyHashable?, typeID: ObjectIdentifier, make: @escaping @MainActor () -> CALayer, update: @escaping @MainActor (CALayer) -> Void) {
        self.id = id
        self.typeID = typeID
        self.make = make
        self.update = update
    }
}

/// A leaf whose layer is created and owned by the layout host.
///
/// ```swift
/// ManagedLayer<CAGradientLayer>(id: "banner", make: { CAGradientLayer() }) {
///     $0.colors = [UIColor.systemIndigo.cgColor, UIColor.systemPink.cgColor]
/// }
/// .height(4)
/// ```
///
/// A layer has no size of its own: give it `.size(…)`, `.height(…)` or `.grow(…)`, or make `L` conform to
/// ``LayerMeasurable``.
public struct ManagedLayer<L: CALayer>: LayoutComponent {
    private let spec: ManagedLayerSpec

    public init(
        id: AnyHashable? = nil,
        make: @escaping @MainActor () -> L,
        update: @escaping @MainActor (L) -> Void = { _ in }
    ) {
        spec = ManagedLayerSpec(
            id: id,
            typeID: ObjectIdentifier(L.self),
            make: make,
            update: { layer in
                if let layer = layer as? L { update(layer) }
            }
        )
    }

    public var layoutNode: LayoutNode { LayoutNode(content: spec) }
}

// MARK: - TextLayer

/// A `CATextLayer` that measures its text.
///
/// `CATextLayer.preferredFrameSize()` is not reliable for wrapped text, so this measures with the same font the layer
/// draws with: wrapped to the width it is offered, or on one line that is truncated when it does not fit. As with
/// ``Label``, a wrapping or truncating layer beside other views needs `.shrink(1)`.
@MainActor
final class MeasuredTextLayer: CATextLayer, LayerMeasurable {
    var text = ""
    var uiFont = UIFont.systemFont(ofSize: UIFont.systemFontSize)
    var wraps = true

    override init() {
        super.init()
        // `wraps` starts true, and `CATextLayer` starts unwrapped: bring them in line so the first update does not
        // see "no change" and skip it.
        isWrapped = true
        truncationMode = .none
    }

    /// Core Animation copies a layer to make its presentation layer.
    override init(layer: Any) {
        super.init(layer: layer)
        if let other = layer as? MeasuredTextLayer {
            text = other.text
            uiFont = other.uiFont
            wraps = other.wraps
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func layoutSize(for constraint: MeasureConstraint) -> CGSize {
        let unlimited = CGFloat.greatestFiniteMagnitude
        let lineHeight = ceil(uiFont.lineHeight)

        if !wraps {
            // One line. It truncates, so it may be squeezed down to nothing.
            if constraint.availableWidth == .minContent, constraint.knownWidth == nil {
                return CGSize(width: 0, height: lineHeight)
            }
            return CGSize(width: ceil(measure(width: unlimited).width), height: lineHeight)
        }
        if constraint.availableWidth == .minContent, constraint.knownWidth == nil {
            let width = LongestWordCache.width(of: .plain(text, uiFont))
            return CGSize(width: width, height: ceil(measure(width: max(width, 1)).height))
        }
        let width = constraint.knownWidth ?? constraint.availableWidth.definiteValue ?? unlimited
        let size = measure(width: width)
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    private func measure(width: CGFloat) -> CGSize {
        (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: uiFont],
            context: nil
        ).size
    }
}

/// Drawn text as a layer. It wraps by default; pass `wraps: false` for one line that truncates.
public struct TextLayer: LayoutComponent {
    public let layoutNode: LayoutNode

    @MainActor
    public init(
        _ text: String,
        font: UIFont = .preferredFont(forTextStyle: .body),
        color: UIColor = .label,
        wraps: Bool = true,
        alignment: CATextLayerAlignmentMode = .natural,
        id: AnyHashable? = nil
    ) {
        layoutNode = ManagedLayer<MeasuredTextLayer>(id: id, make: { MeasuredTextLayer() }) { layer in
            if layer.text != text { layer.text = text; layer.string = text }
            if layer.uiFont != font {
                layer.uiFont = font
                // `UIFont` and `CTFont` are toll-free bridged. Looking the font up by `fontName` would not do: system
                // fonts have internal names (".SFUI-Regular") that CoreText cannot resolve, and it falls back to a serif face.
                layer.font = font as CTFont
                layer.fontSize = font.pointSize
            }
            if layer.wraps != wraps {
                layer.wraps = wraps
                layer.isWrapped = wraps
                layer.truncationMode = wraps ? .none : .end
            }
            let cgColor = color.cgColor
            if layer.foregroundColor != cgColor { layer.foregroundColor = cgColor }
            if layer.alignmentMode != alignment { layer.alignmentMode = alignment }
        }.layoutNode
    }
}
#endif
