import CoreGraphics
import ZDTaffy

/// The lower or upper bound of a `minmax(…)` track.
public struct TrackBound: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case fixed(CGFloat), percent(CGFloat), auto, minContent, maxContent, fitContent(CGFloat), fr(CGFloat)
    }
    let kind: Kind

    public static func fixed(_ points: CGFloat) -> TrackBound { .init(kind: .fixed(points)) }
    public static func percent(_ value: CGFloat) -> TrackBound { .init(kind: .percent(value)) }
    public static let auto = TrackBound(kind: .auto)
    public static let minContent = TrackBound(kind: .minContent)
    public static let maxContent = TrackBound(kind: .maxContent)
    /// Only meaningful as an upper bound.
    public static func fitContent(_ limit: CGFloat) -> TrackBound { .init(kind: .fitContent(limit)) }
    /// A flexible fraction of the leftover space. Only meaningful as an upper bound.
    public static func fr(_ factor: CGFloat) -> TrackBound { .init(kind: .fr(factor)) }

    var asMin: MinTrackSizingFunction {
        switch kind {
        case .fixed(let v): .length(Float(v))
        case .percent(let v): .percent(Float(v / 100))
        case .minContent: .minContent
        case .maxContent: .maxContent
        // `fr` / `fit-content` are not valid minimums.
        case .auto, .fitContent, .fr: .auto
        }
    }

    var asMax: MaxTrackSizingFunction {
        switch kind {
        case .fixed(let v): .length(Float(v))
        case .percent(let v): .percent(Float(v / 100))
        case .auto: .auto
        case .minContent: .minContent
        case .maxContent: .maxContent
        case .fitContent(let v): .fitContentPx(Float(v))
        case .fr(let v): .fr(Float(v))
        }
    }
}

/// How many times a `repeat(…)` group is expanded.
public enum GridRepeat: Hashable, Sendable {
    case count(Int)
    case autoFill
    case autoFit
}

/// One entry of a grid's `columns` / `rows`.
public struct GridTrack: Hashable, Sendable {
    enum Storage: Hashable, Sendable {
        case single(TrackSizingFunction)
        case repeating(GridRepeat, [TrackSizingFunction])
    }
    let storage: Storage

    private init(_ storage: Storage) { self.storage = storage }

    private static func single(min: TrackBound, max: TrackBound) -> GridTrack {
        .init(.single(TrackSizingFunction(min: min.asMin, max: max.asMax)))
    }

    /// A fixed size in points.
    public static func fixed(_ points: CGFloat) -> GridTrack { .single(min: .fixed(points), max: .fixed(points)) }
    public static func percent(_ value: CGFloat) -> GridTrack { .single(min: .percent(value), max: .percent(value)) }
    /// `1fr`, `2fr`, …: a share of the space left after fixed tracks.
    public static func fr(_ factor: CGFloat) -> GridTrack { .single(min: .auto, max: .fr(factor)) }
    public static let auto = GridTrack.single(min: .auto, max: .auto)
    public static let minContent = GridTrack.single(min: .minContent, max: .minContent)
    public static let maxContent = GridTrack.single(min: .maxContent, max: .maxContent)
    public static func minmax(_ min: TrackBound, _ max: TrackBound) -> GridTrack { .single(min: min, max: max) }

    /// `repeat(count, tracks…)`. Every element of `tracks` must be a single track (not another repeat).
    public static func `repeat`(_ count: GridRepeat, _ tracks: [GridTrack]) -> GridTrack {
        let flattened = tracks.compactMap { track -> TrackSizingFunction? in
            if case .single(let function) = track.storage { return function }
            return nil
        }
        return .init(.repeating(count, flattened))
    }

    var component: GridTemplateComponent {
        switch storage {
        case .single(let function):
            return .single(function)
        case .repeating(let count, let functions):
            let taffyCount: RepetitionCount = switch count {
            case .count(let n): .count(UInt16(clamping: max(n, 1)))
            case .autoFill: .autoFill
            case .autoFit: .autoFit
            }
            return .repeat(GridTemplateRepetition(
                count: taffyCount,
                tracks: functions,
                lineNames: Array(repeating: [], count: functions.count + 1)
            ))
        }
    }

    var autoTrack: TrackSizingFunction? {
        if case .single(let function) = storage { return function }
        return nil
    }
}

public enum GridAutoFlow: Hashable, Sendable {
    case row, column, rowDense, columnDense
}
