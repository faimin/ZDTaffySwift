#if canImport(UIKit)
import ObjectiveC
import UIKit
import ZDLayoutCore

/// A view that measures asynchronously, e.g. by asking a background text engine or waiting for an image's size.
///
/// The method runs on the main actor, so it may read the view freely, and may `await` anything: while it waits the
/// main actor is free. It is only used by ``FlexView/layoutAsync()`` and the other `async` layout methods; the
/// ordinary `layoutSubviews` pass cannot wait, so it measures such a view with `sizeThatFits(_:)` /
/// `intrinsicContentSize` as usual. Make those return a sensible estimate (the last known size is a good one).
@MainActor
public protocol AsyncLayoutMeasurable: UIView {
    /// The content size for `constraint`. Same purity rule as ``LayoutMeasurable``: answer from state, because
    /// the layout asks again whenever its own result changes the question.
    func layoutSize(for constraint: MeasureConstraint) async -> CGSize
}

/// A view that can answer measure questions better than `sizeThatFits(_:)`.
///
/// Plain `UIKit` views are measured with `sizeThatFits(_:)`; adopt this for custom views whose size depends on
/// the proposal in a way `sizeThatFits` cannot express.
@MainActor
public protocol LayoutMeasurable: UIView {
    /// The content size for `constraint`. Must be a pure function of the view's current state.
    func layoutSize(for constraint: MeasureConstraint) -> CGSize
}

// Any `UIView` can be placed in a ``LayoutBuilder`` block and takes every modifier, e.g. `avatar.width(40)`.
//
// The conformance is nonisolated because `LayoutComponent` lives in a UI-agnostic module; it asserts that the
// description is built on the main actor, which is where views are created and layout runs.
extension UIView: LayoutComponent {
    nonisolated public var layoutNode: LayoutNode {
        MainActor.assumeIsolated { MainThreadBox(makeLeafNode()) }.value
    }
}

/// Carries a non-`Sendable` value out of `MainActor.assumeIsolated`. It never leaves the main thread.
private struct MainThreadBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

extension UIView {
    @MainActor
    fileprivate func makeLeafNode() -> LayoutNode {
        var style = LayoutStyle()
        style.isHidden = isHidden
        return LayoutNode(
            style: style,
            measure: { [self] constraint in MainActor.assumeIsolated { measuredSize(for: constraint) } },
            asyncMeasure: { @MainActor [self] constraint in
                if let measurable = self as? AsyncLayoutMeasurable {
                    return await measurable.layoutSize(for: constraint)
                }
                return measuredSize(for: constraint)
            },
            content: self
        )
    }

    @MainActor
    fileprivate func measuredSize(for constraint: MeasureConstraint) -> CGSize {
        if let measurable = self as? LayoutMeasurable {
            return measurable.layoutSize(for: constraint)
        }
        if constraint.availableWidth == .minContent, constraint.knownWidth == nil, let label = self as? UILabel {
            return label.minContentSize(height: constraint.knownHeight)
        }

        // A plain `UIView` answers `sizeThatFits` with its *current* size, so a view that does not override it
        // (a custom view that only sets `intrinsicContentSize`) is measured by its intrinsic size instead.
        if !overridesSizeThatFits {
            let intrinsic = intrinsicContentSize
            return CGSize(
                width: intrinsic.width == UIView.noIntrinsicMetric ? 0 : intrinsic.width,
                height: intrinsic.height == UIView.noIntrinsicMetric ? 0 : intrinsic.height
            )
        }

        // The available height is space on offer, not a limit: `UILabel` drops lines that do not fit a finite height,
        // so only a height the layout has actually fixed is passed on.
        return sizeThatFits(CGSize(
            width: constraint.knownWidth ?? constraint.availableWidth.sizeThatFitsValue,
            height: constraint.knownHeight ?? .greatestFiniteMagnitude
        ))
    }

    /// Whether this view's class provides its own `sizeThatFits(_:)`.
    private var overridesSizeThatFits: Bool {
        let selector = #selector(UIView.sizeThatFits(_:))
        guard let own = class_getInstanceMethod(type(of: self), selector),
              let base = class_getInstanceMethod(UIView.self, selector) else { return true }
        return method_getImplementation(own) != method_getImplementation(base)
    }
}

extension UILabel {
    /// UIKit labels wrap or truncate instead of overflowing, so their "smallest size that does not overflow" is
    /// not the whole text: the longest word if the label can wrap, and nothing if it truncates a single line.
    @MainActor
    fileprivate func minContentSize(height: CGFloat?) -> CGSize {
        let width: CGFloat
        if numberOfLines == 1 {
            width = 0
        } else {
            width = longestWordWidth()
        }
        let fitted = sizeThatFits(CGSize(width: max(width, 1), height: height ?? .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitted.height)
    }

    @MainActor
    private func longestWordWidth() -> CGFloat {
        let text = attributedText ?? NSAttributedString(string: self.text ?? "", attributes: [.font: font as Any])
        return LongestWordCache.width(of: text)
    }
}

/// The widest word of a text, remembered by content. A label is asked for its smallest size several times per
/// layout pass and `boundingRect` on its words dominated the cost of a pass, so this is looked up, not recomputed.
/// Content-keyed: changing the text or font simply misses.
@MainActor
private enum LongestWordCache {
    private static var widths: [NSAttributedString: CGFloat] = [:]
    private static let capacity = 2048

    static func width(of text: NSAttributedString) -> CGFloat {
        if let cached = widths[text] { return cached }
        let width = measure(text)
        if widths.count >= capacity { widths.removeAll(keepingCapacity: true) }
        widths[text] = width
        return width
    }

    private static func measure(_ text: NSAttributedString) -> CGFloat {
        let string = text.string as NSString
        var words: [NSRange] = []
        var start: Int?
        for index in 0...string.length {
            let isSeparator = index == string.length
                || CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(string.character(at: index)) ?? " ")
            if isSeparator {
                if let begin = start { words.append(NSRange(location: begin, length: index - begin)) }
                start = nil
            } else if start == nil {
                start = index
            }
        }
        // Measuring every word of a long text is wasteful; the widest is nearly always among the longest.
        let candidates = words.sorted { $0.length > $1.length }.prefix(8)
        let limit = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        return candidates
            .map { text.attributedSubstring(from: $0).boundingRect(with: limit, options: .usesLineFragmentOrigin, context: nil).width }
            .max()
            .map { ceil($0) } ?? 0
    }
}

extension AvailableLength {
    /// The value to hand to `sizeThatFits(_:)`: UIKit has no "unconstrained" except a huge number.
    fileprivate var sizeThatFitsValue: CGFloat {
        switch self {
        case .definite(let value): value
        case .maxContent: .greatestFiniteMagnitude
        case .minContent: 0
        }
    }
}
#endif
