import CoreGraphics

/// A one-dimensional measurement.
///
/// Numeric literals are points (`.width(100)`); percentages are `.percent(50)` or `50.percent`.
/// Not every case is meaningful for every property:
///
/// | Property | Accepted | Anything else is treated as |
/// |---|---|---|
/// | `width`, `height`, `basis` | all cases | – |
/// | `minWidth` … `maxHeight`, `margin`, `inset` | `points`, `percent`, `auto` | `auto` |
/// | `padding`, `border`, `gap` | `points`, `percent` | `0` |
public enum Length: Hashable, Sendable {
    case points(CGFloat)
    /// A percentage of the parent's size: `.percent(50)` is half of it.
    case percent(CGFloat)
    case auto
    /// The smallest size that does not overflow the content.
    case minContent
    /// The size that fits the content without wrapping.
    case maxContent
    /// `min(maxContent, max(minContent, available))`.
    case fitContent
    /// Fills the available space, like CSS `stretch`.
    case stretch
}

extension Length: ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
    public init(integerLiteral value: Int) { self = .points(CGFloat(value)) }
    public init(floatLiteral value: Double) { self = .points(CGFloat(value)) }
}

extension BinaryInteger {
    /// `50.percent` → `Length.percent(50)`.
    public var percent: Length { .percent(CGFloat(self)) }
}

extension BinaryFloatingPoint {
    /// `12.5.percent` → `Length.percent(12.5)`.
    public var percent: Length { .percent(CGFloat(self)) }
}

/// A length per side. `leading` / `trailing` follow the layout direction.
public struct Edges: Hashable, Sendable {
    public var top: Length
    public var leading: Length
    public var bottom: Length
    public var trailing: Length

    public init(top: Length = 0, leading: Length = 0, bottom: Length = 0, trailing: Length = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public init(_ all: Length) {
        self.init(top: all, leading: all, bottom: all, trailing: all)
    }

    public init(horizontal: Length = 0, vertical: Length = 0) {
        self.init(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
    }

    public static let zero = Edges(0)
    public static let auto = Edges(.auto)
}

public enum LayoutDirection: Hashable, Sendable {
    case leftToRight
    case rightToLeft
}
