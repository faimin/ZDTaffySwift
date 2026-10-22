// Hand-written conveniences on top of the BoltFFI-generated bindings in `Generated/`.

import Foundation

// MARK: - Concurrency

// The Rust side guards the tree with a mutex, so a handle can be shared between threads.
// Do not call back into the same tree from inside a `Measure` callback: the lock is not re-entrant.
extension TaffyTree: @unchecked Sendable {}

// MARK: - Style

extension Style {
    /// A style with Taffy's default values (`taffy::Style::DEFAULT`).
    public init() {
        self = defaultStyle()
    }
}

// MARK: - Available space

extension AvailableSize {
    /// Lay out as if the node had all the room it wants.
    public static let maxContent = AvailableSize(width: .maxContent, height: .maxContent)
    /// Lay out as if the node had as little room as possible.
    public static let minContent = AvailableSize(width: .minContent, height: .minContent)

    /// A definite size, e.g. the bounds of a view.
    public static func definite(width: Float, height: Float) -> AvailableSize {
        AvailableSize(width: .definite(width), height: .definite(height))
    }
}

// MARK: - Measure closures

/// Computes the content size of a leaf node.
///
/// - Parameters:
///   - node: The leaf being measured.
///   - known: Dimensions the layout algorithm has already fixed (`nil` means unknown).
///   - available: The space the node may occupy along each axis.
public typealias MeasureFunction = (_ node: NodeId, _ known: OptionalSize, _ available: AvailableSize) -> Size

private final class ClosureMeasure: Measure {
    private let body: MeasureFunction

    init(_ body: @escaping MeasureFunction) {
        self.body = body
    }

    func measure(node: NodeId, known: OptionalSize, available: AvailableSize) -> Size {
        body(node, known, available)
    }
}

extension TaffyTree {
    /// Computes the layout of the subtree under `root`, asking `measure` for leaf content sizes.
    ///
    /// `measure` is invoked synchronously, possibly several times per node, and only for the duration
    /// of this call.
    public func computeLayout(
        root: NodeId,
        available: AvailableSize,
        measure: MeasureFunction
    ) throws {
        try withoutActuallyEscaping(measure) { escapingMeasure in
            try computeLayoutWithMeasure(root: root, available: available, measure: ClosureMeasure(escapingMeasure))
        }
    }
}

// MARK: - Async measure closures

/// Like ``MeasureFunction``, but may suspend, e.g. to measure text on the main actor.
public typealias AsyncMeasureFunction = @Sendable (_ node: NodeId, _ known: OptionalSize, _ available: AvailableSize) async -> Size

private final class ClosureAsyncMeasure: AsyncMeasure {
    private let body: AsyncMeasureFunction

    init(_ body: @escaping AsyncMeasureFunction) {
        self.body = body
    }

    func measure(node: NodeId, known: OptionalSize, available: AvailableSize) async -> Size {
        await body(node, known, available)
    }
}

extension TaffyTree {
    /// Computes the layout of the subtree under `root`, awaiting `measure` for leaf content sizes.
    ///
    /// The layout algorithm is synchronous, so it is re-run until it stops needing new measurements.
    /// `measure` may therefore be asked about sizes that end up unused, and must return the same answer
    /// for the same input. Prefer ``computeLayout(root:available:measure:)`` when the measurement
    /// does not need to suspend.
    ///
    /// - Throws: ``TaffyError/measureDidNotConverge`` if the answers keep changing the questions.
    public func computeLayoutAsync(
        root: NodeId,
        available: AvailableSize,
        measure: @escaping AsyncMeasureFunction
    ) async throws {
        try await computeLayoutWithAsyncMeasure(root: root, available: available, measure: ClosureAsyncMeasure(measure))
    }
}
