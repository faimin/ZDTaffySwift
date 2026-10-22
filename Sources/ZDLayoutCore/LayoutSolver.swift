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
    public var direction: FlowDirection
    /// Points are snapped to multiples of `1 / scale`. Pass the screen's scale (1, 2 or 3).
    public var scale: CGFloat

    public init(direction: FlowDirection = .leftToRight, scale: CGFloat = 1) {
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
    /// Every call measures leaves afresh. The engine asks each leaf about a handful of sizes (about seven), almost
    /// never the same one twice, because it caches a node's results within a call.
    public static func solve(
        _ root: LayoutNode,
        in proposed: ProposedSize,
        sizing: RootSizing = .fill,
        environment: LayoutEnvironment = LayoutEnvironment()
    ) throws -> ResolvedLayout {
        let flat = flatten(adjusted(root, for: proposed, sizing: sizing), environment: environment)
        let layouts = try solveTree(
            styles: flat.styles, nodes: flat.specs, available: proposed.taffy, measure: LeafMeasurer(table: flat.table)
        )
        return resolve(flat, layouts, grid: PixelGrid(scale: environment.scale))
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
        let flat = flatten(adjusted(root, for: proposed, sizing: sizing), environment: environment)
        let measurer = AsyncLeafMeasurer(table: flat.table, isolation: isolation)
        let layouts = try await solveTreeAsync(
            styles: flat.styles, nodes: flat.specs, available: proposed.taffy, measure: measurer
        )
        return resolve(flat, layouts, grid: PixelGrid(scale: environment.scale))
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

    // MARK: Flattening

    /// A tree in the form the engine takes it: pre-order nodes, each naming an entry of a de-duplicated style table.
    private struct Flat {
        var styles: [Style] = []
        var styleIndices: [Style: UInt32] = [:]
        var specs: [NodeSpec] = []
        /// Content-sized leaves must not end up narrower than the content that was measured for them.
        var isMeasured: [Bool] = []
        let table = MeasureTable()

        mutating func index(of style: Style) -> UInt32 {
            if let index = styleIndices[style] { return index }
            let index = UInt32(styles.count)
            styles.append(style)
            styleIndices[style] = index
            return index
        }
    }

    private static func flatten(_ root: LayoutNode, environment: LayoutEnvironment) -> Flat {
        var flat = Flat()
        append(root, environment: environment, to: &flat)
        return flat
    }

    private static func append(_ node: LayoutNode, environment: LayoutEnvironment, to flat: inout Flat) {
        let style = flat.index(of: node.style.resolved(direction: environment.direction))
        flat.specs.append(NodeSpec(style: style, childCount: UInt32(node.children.count)))
        let isLeaf = node.children.isEmpty
        flat.isMeasured.append(isLeaf && (node.measure != nil || node.asyncMeasure != nil))
        flat.table.functions.append(isLeaf ? node.measure : nil)
        flat.table.asyncFunctions.append(isLeaf ? node.asyncMeasure : nil)
        for child in node.children {
            append(child, environment: environment, to: &flat)
        }
    }

    // MARK: Resolving

    private static func resolve(_ flat: Flat, _ layouts: [NodeLayout], grid: PixelGrid) -> ResolvedLayout {
        var cursor = 0
        return resolve(flat, layouts, cursor: &cursor, parentAbsolute: .zero, parentSnappedOrigin: .zero, grid: grid)
    }

    /// Consumes one node and its descendants from the pre-order `layouts`.
    private static func resolve(
        _ flat: Flat,
        _ layouts: [NodeLayout],
        cursor: inout Int,
        parentAbsolute: CGPoint,
        parentSnappedOrigin: CGPoint,
        grid: PixelGrid
    ) -> ResolvedLayout {
        let index = cursor
        cursor += 1
        let layout = layouts[index]
        let absolute = CGRect(
            x: parentAbsolute.x + CGFloat(layout.location.x),
            y: parentAbsolute.y + CGFloat(layout.location.y),
            width: CGFloat(layout.size.width),
            height: CGFloat(layout.size.height)
        )
        // Boxes snap both edges: neighbours then share an exact edge and rounding error cannot accumulate down
        // the tree. Content-sized leaves snap their origin and round the *size up*: a frame a fraction of a pixel
        // narrower than the measured text makes a label truncate, or wrap onto a line nobody made room for.
        let snapped = flat.isMeasured[index] ? grid.snapContent(absolute) : grid.snap(absolute)
        let children = (0..<Int(flat.specs[index].childCount)).map { _ in
            resolve(flat, layouts, cursor: &cursor, parentAbsolute: absolute.origin, parentSnappedOrigin: snapped.origin, grid: grid)
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
    /// Indexed by pre-order position; `nil` for containers and for leaves without that kind of measure.
    var functions: [LeafMeasure?] = []
    var asyncFunctions: [AsyncLeafMeasure?] = []

    func function(at index: Int) -> LeafMeasure? {
        functions.indices.contains(index) ? functions[index] : nil
    }

    func asyncFunction(at index: Int) -> AsyncLeafMeasure? {
        asyncFunctions.indices.contains(index) ? asyncFunctions[index] : nil
    }
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

/// Answers the engine's measure questions by calling the leaves' closures.
///
/// It takes only numbers (see the Rust `TreeMeasure`), so a question costs no encoding. There is no memo: Taffy
/// already caches a node's results within a pass, and measuring showed essentially no repeated question.
private final class LeafMeasurer: TreeMeasure {
    private let table: MeasureTable

    init(table: MeasureTable) { self.table = table }

    func measure(
        node: UInt32,
        knownWidth: Float,
        knownHeight: Float,
        availableWidth: Float,
        availableHeight: Float,
        flags: UInt32
    ) -> Size {
        guard let function = table.function(at: Int(node)) else { return Size(width: 0, height: 0) }
        return engineSize(function(MeasureConstraint(
            knownWidth: flags & 0b1 != 0 ? CGFloat(knownWidth) : nil,
            knownHeight: flags & 0b10 != 0 ? CGFloat(knownHeight) : nil,
            availableWidth: AvailableLength(kind: (flags >> 2) & 0b11, points: availableWidth),
            availableHeight: AvailableLength(kind: (flags >> 4) & 0b11, points: availableHeight)
        )))
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
        if let function = table.asyncFunction(at: Int(node.raw)) {
            return engineSize(await function(request))
        }
        if let function = table.function(at: Int(node.raw)) {
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
    /// Decodes the `kind` / `points` pair `TreeMeasure` uses: 0 definite, 1 min-content, 2 max-content.
    init(kind: UInt32, points: Float) {
        switch kind {
        case 0: self = .definite(CGFloat(points))
        case 1: self = .minContent
        default: self = .maxContent
        }
    }

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
