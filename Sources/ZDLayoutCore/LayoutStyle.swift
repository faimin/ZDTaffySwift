import CoreGraphics
import ZDTaffy

public enum DisplayMode: Hashable, Sendable {
    case flex, grid, block
    /// Takes no space and is not positioned.
    case none
}

public enum FlexAxis: Hashable, Sendable {
    case row, column, rowReverse, columnReverse
}

public enum PositionMode: Hashable, Sendable {
    /// Laid out by the parent, optionally nudged by `inset`.
    case relative
    /// Removed from the flow and placed by `inset` against the parent's padding box.
    case absolute
}

/// Cross-axis alignment (`align-items` / `align-self`).
public enum ItemAlignment: Hashable, Sendable {
    case start, end, center, stretch, baseline, flexStart, flexEnd
}

/// Main-axis distribution (`justify-content` / `align-content`).
public enum ContentDistribution: Hashable, Sendable {
    case start, end, center, stretch, spaceBetween, spaceAround, spaceEvenly, flexStart, flexEnd
}

/// Everything that decides how a node is sized and placed.
///
/// Properties the dedicated fields do not cover can be reached through ``custom``.
public struct LayoutStyle {
    public var display: DisplayMode = .flex
    public var axis: FlexAxis = .row
    public var wraps = false
    public var alignItems: ItemAlignment?
    public var alignSelf: ItemAlignment?
    public var justifyContent: ContentDistribution?
    public var alignContent: ContentDistribution?
    public var grow: CGFloat = 0
    public var shrink: CGFloat = 1
    public var basis: Length = .auto
    public var width: Length = .auto
    public var height: Length = .auto
    public var minWidth: Length = .auto
    public var minHeight: Length = .auto
    public var maxWidth: Length = .auto
    public var maxHeight: Length = .auto
    public var aspectRatio: CGFloat?
    public var margin: Edges = .zero
    public var padding: Edges = .zero
    public var border: Edges = .zero
    public var inset: Edges = .auto
    public var rowGap: Length = 0
    public var columnGap: Length = 0
    public var position: PositionMode = .relative
    public var isHidden = false

    public var columns: [GridTrack] = []
    public var rows: [GridTrack] = []
    public var autoColumns: [GridTrack] = []
    public var autoRows: [GridTrack] = []
    public var autoFlow: GridAutoFlow = .row
    /// 1-based line (negative counts from the end) and span of this item's column placement.
    public var gridColumn: GridItemPlacement = .auto
    public var gridRow: GridItemPlacement = .auto

    /// Escape hatch applied last, with full access to the underlying `ZDTaffy.Style`.
    public var custom: ((inout Style) -> Void)?

    public init() {}
}

/// Where a grid item starts and how far it extends along one axis.
public struct GridItemPlacement: Hashable, Sendable {
    var line: Int?
    var span: Int

    public static let auto = GridItemPlacement(line: nil, span: 1)

    /// Starts at `line` (1-based; negative counts from the end) and covers `span` tracks.
    public static func line(_ line: Int, span: Int = 1) -> GridItemPlacement {
        GridItemPlacement(line: line, span: max(span, 1))
    }

    /// Covers `span` tracks wherever auto-placement puts the item.
    public static func span(_ span: Int) -> GridItemPlacement {
        GridItemPlacement(line: nil, span: max(span, 1))
    }

    var taffy: GridPlacementLine {
        let end = GridPlacement.span(UInt16(clamping: span))
        guard let line else { return GridPlacementLine(start: .auto, end: span > 1 ? end : .auto) }
        return GridPlacementLine(start: .line(Int16(clamping: line)), end: end)
    }
}

// MARK: - Conversion to ZDTaffy

extension Length {
    var dimension: TaffyDimension {
        switch self {
        case .points(let v): .length(Float(v))
        case .percent(let v): .percent(Float(v / 100))
        case .auto: .auto
        case .minContent: .minContent
        case .maxContent: .maxContent
        case .fitContent: .fitContent
        case .stretch: .stretch
        }
    }

    var lengthPercentageAuto: LengthPercentageAuto {
        switch self {
        case .points(let v): .length(Float(v))
        case .percent(let v): .percent(Float(v / 100))
        default: .auto
        }
    }

    var lengthPercentage: LengthPercentage {
        switch self {
        case .points(let v): .length(Float(v))
        case .percent(let v): .percent(Float(v / 100))
        default: .length(0)
        }
    }
}

extension ItemAlignment {
    var taffy: AlignItems {
        let keyword: AlignItemsKeyword = switch self {
        case .start: .start
        case .end: .end
        case .center: .center
        case .stretch: .stretch
        case .baseline: .baseline
        case .flexStart: .flexStart
        case .flexEnd: .flexEnd
        }
        return AlignItems(keyword: keyword, safety: .default)
    }
}

extension ContentDistribution {
    var taffy: AlignContent {
        let keyword: AlignContentKeyword = switch self {
        case .start: .start
        case .end: .end
        case .center: .center
        case .stretch: .stretch
        case .spaceBetween: .spaceBetween
        case .spaceAround: .spaceAround
        case .spaceEvenly: .spaceEvenly
        case .flexStart: .flexStart
        case .flexEnd: .flexEnd
        }
        return AlignContent(keyword: keyword, safety: .default)
    }
}

extension LayoutStyle {
    /// Lowers this style to a `ZDTaffy.Style`, resolving `leading` / `trailing` for `direction`.
    func resolved(direction: LayoutDirection) -> Style {
        var s = Style()
        s.display = switch display {
        case _ where isHidden: .none
        case .flex: .flex
        case .grid: .grid
        case .block: .block
        case .none: .none
        }
        s.direction = direction == .rightToLeft ? .rtl : .ltr
        s.flexDirection = switch axis {
        case .row: .row
        case .column: .column
        case .rowReverse: .rowReverse
        case .columnReverse: .columnReverse
        }
        s.flexWrap = wraps ? .wrap : .noWrap
        s.alignItems = alignItems.map(\.taffy) ?? s.alignItems
        s.alignSelf = alignSelf?.taffy
        s.justifyContent = justifyContent.map(\.taffy) ?? s.justifyContent
        s.alignContent = alignContent.map(\.taffy) ?? s.alignContent
        s.flexGrow = Float(grow)
        s.flexShrink = Float(shrink)
        s.flexBasis = basis.dimension
        s.size = DimensionSize(width: width.dimension, height: height.dimension)
        s.minSize = LengthPercentageAutoSize(width: minWidth.lengthPercentageAuto, height: minHeight.lengthPercentageAuto)
        s.maxSize = LengthPercentageAutoSize(width: maxWidth.lengthPercentageAuto, height: maxHeight.lengthPercentageAuto)
        s.aspectRatio = aspectRatio.map(Float.init)
        s.margin = margin.autoRect(direction)
        s.inset = inset.autoRect(direction)
        s.padding = padding.rect(direction)
        s.border = border.rect(direction)
        s.gap = LengthPercentageSize(width: columnGap.lengthPercentage, height: rowGap.lengthPercentage)
        s.position = position == .absolute ? .absolute : .relative

        s.gridTemplateColumns = columns.map(\.component)
        s.gridTemplateRows = rows.map(\.component)
        s.gridAutoColumns = autoColumns.compactMap(\.autoTrack)
        s.gridAutoRows = autoRows.compactMap(\.autoTrack)
        s.gridAutoFlow = switch autoFlow {
        case .row: .row
        case .column: .column
        case .rowDense: .rowDense
        case .columnDense: .columnDense
        }
        s.gridColumn = gridColumn.taffy
        s.gridRow = gridRow.taffy

        custom?(&s)
        return s
    }
}

private extension Edges {
    /// Maps logical sides to physical ones.
    func physical(_ direction: LayoutDirection) -> (top: Length, left: Length, bottom: Length, right: Length) {
        direction == .leftToRight
            ? (top, leading, bottom, trailing)
            : (top, trailing, bottom, leading)
    }

    func autoRect(_ direction: LayoutDirection) -> LengthPercentageAutoRect {
        let p = physical(direction)
        return LengthPercentageAutoRect(
            left: p.left.lengthPercentageAuto,
            right: p.right.lengthPercentageAuto,
            top: p.top.lengthPercentageAuto,
            bottom: p.bottom.lengthPercentageAuto
        )
    }

    func rect(_ direction: LayoutDirection) -> LengthPercentageRect {
        let p = physical(direction)
        return LengthPercentageRect(
            left: p.left.lengthPercentage,
            right: p.right.lengthPercentage,
            top: p.top.lengthPercentage,
            bottom: p.bottom.lengthPercentage
        )
    }
}
