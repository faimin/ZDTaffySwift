import CoreGraphics
import ZDTaffy

/// The space the root may occupy.
public struct ProposedSize: Hashable, Sendable {
    public var width: AvailableLength
    public var height: AvailableLength

    public init(width: AvailableLength, height: AvailableLength) {
        self.width = width
        self.height = height
    }

    public init(_ size: CGSize) {
        self.init(width: .definite(size.width), height: .definite(size.height))
    }

    /// Lay out at the content's natural size.
    public static let unconstrained = ProposedSize(width: .maxContent, height: .maxContent)
    /// Lay out at the smallest size that fits the content.
    public static let compressed = ProposedSize(width: .minContent, height: .minContent)
}

/// Facts about where the layout will be displayed.
public struct LayoutEnvironment: Hashable, Sendable {
    public var direction: LayoutDirection
    /// Points are snapped to multiples of `1 / scale`. Pass the screen's scale (1, 2 or 3).
    public var scale: CGFloat

    public init(direction: LayoutDirection = .leftToRight, scale: CGFloat = 1) {
        self.direction = direction
        self.scale = scale
    }
}

/// The solved frame of a node and its children, mirroring the shape of the ``LayoutNode`` tree.
public struct ResolvedLayout: Sendable {
    /// Relative to the parent's origin, snapped to the pixel grid.
    public var frame: CGRect
    /// Relative to the root's origin, snapped to the pixel grid.
    public var absoluteFrame: CGRect
    public var children: [ResolvedLayout]

    /// The leaves of this subtree in depth-first order (a node without children is a leaf).
    public var leaves: [ResolvedLayout] {
        children.isEmpty ? [self] : children.flatMap(\.leaves)
    }
}

/// How the root node relates to the proposed size.
public enum RootSizing: Hashable, Sendable {
    /// The root takes the proposed size on every axis where one is definite and its own `width` / `height`
    /// is `auto`. Use this to lay out into a view whose bounds are already decided.
    case fill
    /// The root takes its natural size, but never more than a definite proposal (`fit-content`): content that
    /// can wrap does. Use this to answer `sizeThatFits`.
    case fit
}

public enum LayoutSolver {
    /// Computes the layout of `root`.
    ///
    /// The solver is synchronous and has no actor isolation; `measure` closures run on the calling thread.
    /// Every call measures leaves afresh, but identical questions inside one call are answered once.
    public static func solve(
        _ root: LayoutNode,
        in proposed: ProposedSize,
        sizing: RootSizing = .fill,
        environment: LayoutEnvironment = LayoutEnvironment()
    ) throws -> ResolvedLayout {
        let root = adjusted(root, for: proposed, sizing: sizing)

        let tree = TaffyTree()
        // Rounding to whole points is wrong on 2x / 3x screens; ``PixelGrid`` snaps the final result instead.
        tree.disableRounding()

        let table = MeasureTable()
        let built = try build(root, in: tree, environment: environment, table: table)
        try tree.computeLayoutWithMeasure(root: built.id, available: proposed.taffy, measure: LeafMeasurer(table: table))

        let grid = PixelGrid(scale: environment.scale)
        return try resolve(built, in: tree, parentAbsolute: .zero, parentSnappedOrigin: .zero, grid: grid)
    }

    /// Computes the layout of `root`, letting leaves measure asynchronously.
    ///
    /// A leaf's ``LayoutNode/asyncMeasure`` is preferred; one with only a synchronous ``LayoutNode/measure`` is
    /// called on the caller's actor, so views that must be touched on the main actor are safe when this is called
    /// from there. The layout algorithm itself is synchronous, so it is re-run until a pass needs no new
    /// measurements: a leaf can be asked about sizes that end up unused, and must answer the same question the same
    /// way every time.
    ///
    /// - Throws: ``TaffyError`` from the engine, e.g. `measureDidNotConverge` if the answers never settle.
    public static func solveAsync(
        _ root: LayoutNode,
        in proposed: ProposedSize,
        sizing: RootSizing = .fill,
        environment: LayoutEnvironment = LayoutEnvironment(),
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> ResolvedLayout {
        let root = adjusted(root, for: proposed, sizing: sizing)

        let tree = TaffyTree()
        tree.disableRounding()

        let table = MeasureTable()
        let built = try build(root, in: tree, environment: environment, table: table)
        let measurer = AsyncLeafMeasurer(table: table, isolation: isolation)
        try await tree.computeLayoutWithAsyncMeasure(root: built.id, available: proposed.taffy, measure: measurer)

        let grid = PixelGrid(scale: environment.scale)
        return try resolve(built, in: tree, parentAbsolute: .zero, parentSnappedOrigin: .zero, grid: grid)
    }

    /// Applies the root sizing rule to the proposal.
    private static func adjusted(_ root: LayoutNode, for proposed: ProposedSize, sizing: RootSizing) -> LayoutNode {
        var root = root
        if case .definite(let width) = proposed.width, root.style.width == .auto {
            // `fit-content`: Taffy ignores that keyword on the root, so cap the root with the proposal instead.
            if sizing == .fill { root.style.width = .points(width) } else if root.style.maxWidth == .auto { root.style.maxWidth = .points(width) }
        }
        if case .definite(let height) = proposed.height, root.style.height == .auto {
            if sizing == .fill { root.style.height = .points(height) } else if root.style.maxHeight == .auto { root.style.maxHeight = .points(height) }
        }
        return root
    }

    // MARK: Building

    private struct Built {
        let id: NodeId
        let children: [Built]
        /// Content-sized leaves must not end up narrower than the content that was measured for them.
        let isMeasured: Bool
    }

    private static func build(
        _ node: LayoutNode,
        in tree: TaffyTree,
        environment: LayoutEnvironment,
        table: MeasureTable
    ) throws -> Built {
        let style = node.style.resolved(direction: environment.direction)
        if node.children.isEmpty {
            let id = try tree.newLeaf(style: style)
            if let measure = node.measure { table.functions[id] = measure }
            if let asyncMeasure = node.asyncMeasure { table.asyncFunctions[id] = asyncMeasure }
            return Built(id: id, children: [], isMeasured: node.measure != nil || node.asyncMeasure != nil)
        }
        let children = try node.children.map { try build($0, in: tree, environment: environment, table: table) }
        let id = try tree.newWithChildren(style: style, children: children.map(\.id))
        return Built(id: id, children: children, isMeasured: false)
    }

    // MARK: Resolving

    private static func resolve(
        _ built: Built,
        in tree: TaffyTree,
        parentAbsolute: CGPoint,
        parentSnappedOrigin: CGPoint,
        grid: PixelGrid
    ) throws -> ResolvedLayout {
        let layout = try tree.layout(node: built.id)
        let absolute = CGRect(
            x: parentAbsolute.x + CGFloat(layout.location.x),
            y: parentAbsolute.y + CGFloat(layout.location.y),
            width: CGFloat(layout.size.width),
            height: CGFloat(layout.size.height)
        )
        // Boxes snap both edges: neighbours then share an exact edge and rounding error cannot accumulate down
        // the tree. Content-sized leaves snap their origin and round the *size up*: a frame a fraction of a pixel
        // narrower than the measured text makes a label truncate, or wrap onto a line nobody made room for.
        let snapped = built.isMeasured ? grid.snapContent(absolute) : grid.snap(absolute)
        let children = try built.children.map {
            try resolve($0, in: tree, parentAbsolute: absolute.origin, parentSnappedOrigin: snapped.origin, grid: grid)
        }
        return ResolvedLayout(
            frame: CGRect(
                x: snapped.minX - parentSnappedOrigin.x,
                y: snapped.minY - parentSnappedOrigin.y,
                width: snapped.width,
                height: snapped.height
            ),
            absoluteFrame: snapped,
            children: children
        )
    }
}

/// Snaps rectangles to the device pixel grid.
struct PixelGrid {
    let scale: CGFloat

    init(scale: CGFloat) {
        self.scale = scale > 0 ? scale : 1
    }

    func snap(_ value: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }

    /// Rounds the size up to whole pixels, ignoring floating point noise, and the origin to the nearest pixel.
    func snapContent(_ rect: CGRect) -> CGRect {
        func up(_ value: CGFloat) -> CGFloat { ((value * scale) - 1e-3).rounded(.up) / scale }
        return CGRect(x: snap(rect.minX), y: snap(rect.minY), width: up(rect.width), height: up(rect.height))
    }

    /// Snaps the left/top and right/bottom edges independently so adjacent rectangles stay flush.
    func snap(_ rect: CGRect) -> CGRect {
        let minX = snap(rect.minX), minY = snap(rect.minY)
        let maxX = snap(rect.maxX), maxY = snap(rect.maxY)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - Measuring

/// The measure functions of a tree's leaves, by node.
private final class MeasureTable {
    var functions: [NodeId: LeafMeasure] = [:]
    var asyncFunctions: [NodeId: AsyncLeafMeasure] = [:]
}

private func constraint(_ node: NodeId, _ known: OptionalSize, _ available: AvailableSize) -> MeasureConstraint {
    MeasureConstraint(
        knownWidth: known.width.map { CGFloat($0) },
        knownHeight: known.height.map { CGFloat($0) },
        availableWidth: AvailableLength(available.width),
        availableHeight: AvailableLength(available.height)
    )
}

private func engineSize(_ size: CGSize) -> Size {
    Size(width: Float(max(size.width, 0)), height: Float(max(size.height, 0)))
}

/// Answers the engine's measure questions by calling the leaves' closures, memoising per pass.
private final class LeafMeasurer: Measure {
    private let table: MeasureTable
    private var answers: [Question: Size] = [:]

    init(table: MeasureTable) { self.table = table }

    private struct Question: Hashable {
        let node: NodeId
        let known: OptionalSize
        let available: AvailableSize
    }

    func measure(node: NodeId, known: OptionalSize, available: AvailableSize) -> Size {
        let question = Question(node: node, known: known, available: available)
        if let answer = answers[question] { return answer }

        let answer: Size
        if let function = table.functions[node] {
            answer = engineSize(function(constraint(node, known, available)))
        } else {
            answer = Size(width: 0, height: 0)
        }
        answers[question] = answer
        return answer
    }
}

/// The asynchronous counterpart. The engine remembers answers across its own passes, so there is no memo here.
///
/// It is handed to the engine, which may call it from any executor, so it is marked `@unchecked Sendable`. That is
/// sound because calls are sequential (the engine awaits one question at a time) and each closure is run where it
/// belongs: asynchronous ones are awaited as they are, synchronous ones are hopped to the caller's actor.
private final class AsyncLeafMeasurer: AsyncMeasure, @unchecked Sendable {
    private let table: MeasureTable
    private let isolation: (any Actor)?

    init(table: MeasureTable, isolation: (any Actor)?) {
        self.table = table
        self.isolation = isolation
    }

    func measure(node: NodeId, known: OptionalSize, available: AvailableSize) async -> Size {
        let request = constraint(node, known, available)
        if let function = table.asyncFunctions[node] {
            return engineSize(await function(request))
        }
        if let function = table.functions[node] {
            return engineSize(await runSynchronously(on: isolation, request, function))
        }
        return Size(width: 0, height: 0)
    }

    /// Runs `function` on `actor` (or wherever we are when there is none).
    private func runSynchronously(on actor: isolated (any Actor)?, _ request: MeasureConstraint, _ function: LeafMeasure) -> CGSize {
        function(request)
    }
}

private extension AvailableLength {
    init(_ space: AvailableSpace) {
        switch space {
        case .definite(let v): self = .definite(CGFloat(v))
        case .minContent: self = .minContent
        case .maxContent: self = .maxContent
        }
    }

    var taffy: AvailableSpace {
        switch self {
        case .definite(let v): .definite(Float(v))
        case .minContent: .minContent
        case .maxContent: .maxContent
        }
    }
}

private extension ProposedSize {
    var taffy: AvailableSize { AvailableSize(width: width.taffy, height: height.taffy) }
}
