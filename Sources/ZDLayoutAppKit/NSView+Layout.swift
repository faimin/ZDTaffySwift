#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
import ZDLayoutCore

/// A view that can answer measure questions better than the generic rules below.
@MainActor
public protocol LayoutMeasurable: NSView {
    /// The content size for `constraint`. Must be a pure function of the view's current state.
    func layoutSize(for constraint: MeasureConstraint) -> CGSize
}

// Any `NSView` can be placed in a ``LayoutBuilder`` block and takes every modifier, e.g. `icon.size(24)`.
//
// The conformance is nonisolated because `LayoutComponent` lives in a UI-agnostic module; it asserts that the
// description is built on the main actor, which is where views are created and layout runs.
extension NSView: LayoutComponent {
    nonisolated public var layoutNode: LayoutNode {
        MainActor.assumeIsolated { MainThreadBox(makeLeafNode()) }.value
    }
}

/// Carries a non-`Sendable` value out of `MainActor.assumeIsolated`. It never leaves the main thread.
private struct MainThreadBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

extension NSView {
    @MainActor
    fileprivate func makeLeafNode() -> LayoutNode {
        var style = LayoutStyle()
        style.isHidden = isHidden
        return LayoutNode(
            style: style,
            measure: { [self] constraint in MainActor.assumeIsolated { measuredSize(for: constraint) } },
            content: self
        )
    }

    /// In order: a ``LayoutMeasurable`` view; a text control (measured by its cell at the offered width, with the
    /// same smallest-width rule as `UILabel` in ``ZDLayout``); otherwise `intrinsicContentSize`, falling back to
    /// `fittingSize` for a view that has none.
    @MainActor
    fileprivate func measuredSize(for constraint: MeasureConstraint) -> CGSize {
        if let measurable = self as? LayoutMeasurable {
            return measurable.layoutSize(for: constraint)
        }
        if let control = self as? NSTextField {
            return control.textSize(for: constraint)
        }
        if let control = self as? NSControl, let cell = control.cell {
            let width = constraint.knownWidth ?? constraint.availableWidth.definiteValue ?? .greatestFiniteMagnitude
            return cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude))
        }
        let intrinsic = intrinsicContentSize
        if intrinsic.width == NSView.noIntrinsicMetric && intrinsic.height == NSView.noIntrinsicMetric {
            return fittingSize
        }
        return CGSize(
            width: intrinsic.width == NSView.noIntrinsicMetric ? 0 : intrinsic.width,
            height: intrinsic.height == NSView.noIntrinsicMetric ? 0 : intrinsic.height
        )
    }
}

extension NSTextField {
    /// Whether the text can run onto further lines (as opposed to being truncated on one).
    fileprivate var canWrap: Bool {
        guard let cell else { return false }
        return cell.wraps && maximumNumberOfLines != 1
    }

    @MainActor
    fileprivate func textSize(for constraint: MeasureConstraint) -> CGSize {
        guard let cell else { return intrinsicContentSize }
        let unlimited = CGFloat.greatestFiniteMagnitude

        if constraint.availableWidth == .minContent, constraint.knownWidth == nil {
            // Like a label in ``ZDLayout``: wrap at the longest word, or truncate down to nothing.
            let width = canWrap ? LongestWordCache.width(of: attributedStringValue) : 0
            let height = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: max(width, 1), height: unlimited)).height
            return CGSize(width: width, height: height)
        }
        let width = constraint.knownWidth ?? constraint.availableWidth.definiteValue ?? unlimited
        return cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: unlimited))
    }
}

/// The widest word of a text, remembered by content: a text field is asked for its smallest size several times per
/// layout pass, and measuring its words each time dominated the cost of a pass in the UIKit layer.
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
        let candidates = words.sorted { $0.length > $1.length }.prefix(8)
        let limit = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        return candidates
            .map { text.attributedSubstring(from: $0).boundingRect(with: limit, options: .usesLineFragmentOrigin).width }
            .max()
            .map { ceil($0) } ?? 0
    }
}
#endif
