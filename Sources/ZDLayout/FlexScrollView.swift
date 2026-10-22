#if canImport(UIKit)
import UIKit
import ZDLayoutCore

/// A scroll view whose content is laid out with Flexbox / Grid and sized along the scrolling axis.
///
/// The content fills the scroll view across the axis and takes its natural size along it; `contentSize` follows
/// automatically. Describe the content like ``FlexView``.
@MainActor
open class FlexScrollView: UIScrollView, LayoutMeasurable {
    public enum Axis: Hashable, Sendable {
        case vertical, horizontal
    }

    public let axis: Axis

    public var insets: FlexInsets = .none {
        didSet {
            guard insets != oldValue else { return }
            setNeedsLayout()
        }
    }

    private let engine = FlexEngine()
    private let contentBuilder: (@MainActor () -> [LayoutNode])?

    /// For subclasses that override ``body()``.
    public init(axis: Axis = .vertical) {
        self.axis = axis
        contentBuilder = nil
        super.init(frame: .zero)
        configureMargins()
    }

    public init(axis: Axis = .vertical, insets: FlexInsets = .none, @LayoutBuilder content: @escaping @MainActor () -> [LayoutNode]) {
        self.axis = axis
        contentBuilder = content
        self.insets = insets
        super.init(frame: .zero)
        configureMargins()
    }

    public required init?(coder: NSCoder) {
        axis = .vertical
        contentBuilder = nil
        super.init(coder: coder)
        configureMargins()
    }

    /// A scroll view already makes room for the safe area through `contentInsetAdjustmentBehavior`; letting the
    /// layout margins include it too would count it twice (a tall empty band above the content).
    private func configureMargins() {
        insetsLayoutMarginsFromSafeArea = false
    }

    @LayoutBuilder
    open func body() -> [LayoutNode] {
        contentBuilder?() ?? []
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        let size = engine.layout(children: body(), insets: insets, host: self, origin: .zero, proposed: scrollingProposal(for: bounds.size))
        if contentSize != size { contentSize = size }
    }

    open override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        if insets == .safeArea { setNeedsLayout() }
    }

    /// Fixed across the axis, unconstrained along it.
    private func scrollingProposal(for size: CGSize) -> ProposedSize {
        switch axis {
        case .vertical: ProposedSize(width: .definite(size.width), height: .maxContent)
        case .horizontal: ProposedSize(width: .maxContent, height: .definite(size.height))
        }
    }

    /// The content size for `size`, i.e. the `contentSize` the scroll view would end up with.
    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        engine.fittingSize(children: body(), insets: insets, host: self, proposed: scrollingProposal(for: size))
    }

    /// Lays the content out now, awaiting leaves that adopt ``AsyncLayoutMeasurable``, and updates `contentSize`.
    /// See ``FlexView/layoutAsync()``.
    public func layoutAsync() async {
        let size = await engine.layoutAsync(children: body(), insets: insets, host: self, origin: .zero, proposed: scrollingProposal(for: bounds.size))
        if contentSize != size { contentSize = size }
    }

    public func layoutSize(for constraint: MeasureConstraint) -> CGSize {
        engine.fittingSize(children: body(), insets: insets, host: self, proposed: ProposedSize(
            width: constraint.knownWidth.map { .definite($0) } ?? constraint.availableWidth,
            height: constraint.knownHeight.map { .definite($0) } ?? constraint.availableHeight
        ))
    }

    nonisolated open override var debugDescription: String {
        MainActor.assumeIsolated { "\(super.debugDescription)\n\(engine.treeDescription)" }
    }
}
#endif
