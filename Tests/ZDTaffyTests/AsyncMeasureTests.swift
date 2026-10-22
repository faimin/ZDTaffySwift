import Foundation
import Testing
@testable import ZDTaffy

/// A stand-in for wrapped text: `characters` glyphs of `glyphWidth` points, 10 points tall per line.
private func textSize(characters: Int, glyphWidth: Float, in available: AvailableSpace) -> Size {
    let fullWidth = Float(characters) * glyphWidth
    switch available {
    case .definite(let width) where width < fullWidth:
        let lines = (fullWidth / max(width, glyphWidth)).rounded(.up)
        return Size(width: width, height: lines * 10)
    case .minContent:
        return Size(width: glyphWidth, height: Float(characters) * 10)
    default:
        return Size(width: fullWidth, height: 10)
    }
}

@Suite("Async measure")
struct AsyncMeasureTests {
    @Test func awaitsMeasureAndSizesLeaf() async throws {
        let tree = TaffyTree()
        let leaf = try tree.newLeaf(style: Style())

        try await tree.computeLayoutAsync(root: leaf, available: .maxContent) { _, _, _ in
            try? await Task.sleep(nanoseconds: 1_000_000)
            return Size(width: 40, height: 12)
        }

        #expect(try tree.layout(node: leaf).size == Size(width: 40, height: 12))
    }

    @Test func measureMayHopToMainActor() async throws {
        let tree = TaffyTree()
        let leaf = try tree.newLeaf(style: Style())

        let sawMainThread = LockedBox(false)
        try await tree.computeLayoutAsync(root: leaf, available: .maxContent) { _, _, _ in
            await MainActor.run {
                sawMainThread.set(Thread.isMainThread)
                return Size(width: 7, height: 9)
            }
        }

        #expect(sawMainThread.get())
        #expect(try tree.layout(node: leaf).size == Size(width: 7, height: 9))
    }

    @Test func matchesSynchronousLayoutForWrappingContent() async throws {
        // Two "paragraphs" side by side whose height depends on the width they are given.
        func build(_ tree: TaffyTree) throws -> (root: NodeId, leaves: [NodeId]) {
            var itemStyle = Style()
            itemStyle.flexGrow = 1
            itemStyle.flexBasis = .length(0)
            let leaves = try [itemStyle, itemStyle].map { try tree.newLeaf(style: $0) }

            var rootStyle = Style()
            rootStyle.display = .flex
            rootStyle.size = DimensionSize(width: .length(100), height: .auto)
            return (try tree.newWithChildren(style: rootStyle, children: leaves), leaves)
        }
        let syncTree = TaffyTree()
        let (syncRoot, syncLeaves) = try build(syncTree)
        let asyncTree = TaffyTree()
        let (asyncRoot, asyncLeaves) = try build(asyncTree)

        @Sendable func glyphs(for node: NodeId, among leaves: [NodeId]) -> Int {
            leaves.firstIndex(of: node) == 0 ? 12 : 30
        }

        try syncTree.computeLayout(root: syncRoot, available: .maxContent) { node, _, available in
            textSize(characters: glyphs(for: node, among: syncLeaves), glyphWidth: 5, in: available.width)
        }
        try await asyncTree.computeLayoutAsync(root: asyncRoot, available: .maxContent) { node, _, available in
            textSize(characters: glyphs(for: node, among: asyncLeaves), glyphWidth: 5, in: available.width)
        }

        for (syncLeaf, asyncLeaf) in zip(syncLeaves, asyncLeaves) {
            #expect(try syncTree.layout(node: syncLeaf) == asyncTree.layout(node: asyncLeaf))
        }
        #expect(try syncTree.layout(node: syncRoot) == asyncTree.layout(node: asyncRoot))
        // Sanity: the wrapped paragraph really is taller than one line.
        #expect(try asyncTree.layout(node: asyncLeaves[1]).size.height > 10)
    }

    @Test func protocolImplementationCanBeUsedDirectly() async throws {
        final class Fixed: AsyncMeasure {
            func measure(node: NodeId, known: OptionalSize, available: AvailableSize) async -> Size {
                Size(width: 3, height: 4)
            }
        }

        let tree = TaffyTree()
        let leaf = try tree.newLeaf(style: Style())
        try await tree.computeLayoutWithAsyncMeasure(root: leaf, available: .maxContent, measure: Fixed())

        #expect(try tree.layout(node: leaf).size == Size(width: 3, height: 4))
    }

    @Test func invalidRootThrows() async throws {
        let tree = TaffyTree()
        let node = try tree.newLeaf(style: Style())
        _ = try tree.remove(node: node)

        await #expect(throws: TaffyError.invalidInputNode) {
            try await tree.computeLayoutAsync(root: node, available: .maxContent) { _, _, _ in Size(width: 1, height: 1) }
        }
    }
}

private final class LockedBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func get() -> Value { lock.withLock { value } }
    func set(_ newValue: Value) { lock.withLock { value = newValue } }
}
