#if canImport(UIKit)
import UIKit
import ZDLayoutCore

/// A view that lays its subviews out with Flexbox / Grid.
///
/// Describe the content with ``body()`` (subclass) or the `content` closure; it is re-evaluated on every layout
/// pass, so it can read your state directly. Change state, then call `setNeedsLayout()`.
///
/// ```swift
/// final class Header: FlexView {
///     let avatar = UIImageView(), title = UILabel()
///
///     @LayoutBuilder override func body() -> [LayoutNode] {
///         Row(gap: 12, alignItems: .center) {
///             avatar.size(40)
///             title.grow(1)
///         }
///         .padding(16)
///     }
/// }
/// ```
///
/// Swift does not carry a result builder over to an override, so repeat `@LayoutBuilder` on `body()`.
///
/// The view takes part in UIKit's layout: it positions subviews in `layoutSubviews`, answers `sizeThatFits(_:)`,
/// and reports `intrinsicContentSize` (call `invalidateIntrinsicContentSize()` when it changes).
@MainActor
open class FlexView: UIView, LayoutMeasurable {
    /// Space reserved for system chrome. Defaults to none.
    public var insets: FlexInsets = .none {
        didSet {
            guard insets != oldValue else { return }
            setNeedsLayout()
            invalidateIntrinsicContentSize()
        }
    }

    #if DEBUG
    /// Outlines every node while debugging. Only available in `DEBUG` builds.
    public var showsLayoutDebugOverlay = false {
        didSet { setNeedsLayout() }
    }
    #endif

    private let engine = FlexEngine()
    private var widthUsedForIntrinsicSize: CGFloat = 0
    private let contentBuilder: (@MainActor () -> [LayoutNode])?

    /// For subclasses that override ``body()``.
    public override init(frame: CGRect) {
        contentBuilder = nil
        super.init(frame: frame)
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

    /// The description of this view's content. The default evaluates the `content` closure.
    @LayoutBuilder
    open func body() -> [LayoutNode] {
        contentBuilder?() ?? []
    }

    // MARK: Layout

    open override func layoutSubviews() {
        super.layoutSubviews()
        // Height depends on width, but Auto Layout only asks `intrinsicContentSize`. Like `UILabel`, report the
        // height for the width we actually have, and ask to be measured again when that width changes.
        if bounds.width != widthUsedForIntrinsicSize {
            widthUsedForIntrinsicSize = bounds.width
            invalidateIntrinsicContentSize()
        }
        engine.layout(children: body(), insets: insets, host: self, proposed: ProposedSize(bounds.size))
        #if DEBUG
        engine.updateOverlay(in: self, isVisible: showsLayoutDebugOverlay)
        #endif
    }

    open override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        if insets == .safeArea { setNeedsLayout() }
    }

    open override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
        if insets == .layoutMargins { setNeedsLayout() }
    }

    // MARK: Sizing

    /// Sizes the content within `size`. A non-positive, non-finite or huge dimension means "no limit".
    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        fittingSize(ProposedSize(width: proposal(for: size.width), height: proposal(for: size.height)))
    }

    /// The natural width, and the height for the current width (the natural height before the first layout).
    open override var intrinsicContentSize: CGSize {
        let natural = fittingSize(.unconstrained)
        guard bounds.width > 0, natural.width > bounds.width else { return natural }
        return CGSize(width: natural.width, height: fittingSize(ProposedSize(width: .definite(bounds.width), height: .maxContent)).height)
    }

    open override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        // Only a `required` priority pins an axis to the target; anything lower asks for the natural size.
        fittingSize(ProposedSize(
            width: horizontalFittingPriority == .required ? proposal(for: targetSize.width) : .maxContent,
            height: verticalFittingPriority == .required ? proposal(for: targetSize.height) : .maxContent
        ))
    }

    public func layoutSize(for constraint: MeasureConstraint) -> CGSize {
        fittingSize(ProposedSize(
            width: constraint.knownWidth.map { .definite($0) } ?? constraint.availableWidth,
            height: constraint.knownHeight.map { .definite($0) } ?? constraint.availableHeight
        ))
    }

    private func fittingSize(_ proposed: ProposedSize) -> CGSize {
        engine.fittingSize(children: body(), insets: insets, host: self, proposed: proposed)
    }

    // MARK: Debugging

    /// The laid-out tree with frames, as of the last layout pass.
    nonisolated open override var debugDescription: String {
        MainActor.assumeIsolated { "\(super.debugDescription)\n\(engine.treeDescription)" }
    }
}
#endif
