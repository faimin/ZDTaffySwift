import Testing
@testable import ZDTaffy

private func lengthSize(_ width: Float, _ height: Float) -> DimensionSize {
    DimensionSize(width: .length(width), height: .length(height))
}

@Suite("Flexbox")
struct FlexboxTests {
    @Test func rowSplitsSpaceByFlexGrow() throws {
        let tree = TaffyTree()

        var child = Style()
        child.flexGrow = 1
        let a = try tree.newLeaf(style: child)
        let b = try tree.newLeaf(style: child)

        var rootStyle = Style()
        rootStyle.display = .flex
        rootStyle.size = lengthSize(200, 100)
        let root = try tree.newWithChildren(style: rootStyle, children: [a, b])

        try tree.computeLayout(root: root, available: .maxContent)

        let layoutA = try tree.layout(node: a)
        let layoutB = try tree.layout(node: b)
        #expect(layoutA.size == Size(width: 100, height: 100))
        #expect(layoutA.location == Point(x: 0, y: 0))
        #expect(layoutB.size == Size(width: 100, height: 100))
        #expect(layoutB.location == Point(x: 100, y: 0))
    }

    @Test func columnWithGapAndPadding() throws {
        let tree = TaffyTree()

        var child = Style()
        child.size = lengthSize(50, 20)
        let a = try tree.newLeaf(style: child)
        let b = try tree.newLeaf(style: child)

        var rootStyle = Style()
        rootStyle.display = .flex
        rootStyle.flexDirection = .column
        rootStyle.size = lengthSize(100, 200)
        rootStyle.gap = LengthPercentageSize(width: .length(0), height: .length(10))
        rootStyle.padding = LengthPercentageRect(
            left: .length(5), right: .length(5), top: .length(8), bottom: .length(8)
        )
        let root = try tree.newWithChildren(style: rootStyle, children: [a, b])

        try tree.computeLayout(root: root, available: .maxContent)

        #expect(try tree.layout(node: a).location == Point(x: 5, y: 8))
        #expect(try tree.layout(node: b).location == Point(x: 5, y: 38))
    }

    @Test func justifyContentCentersChild() throws {
        let tree = TaffyTree()

        var child = Style()
        child.size = lengthSize(40, 40)
        let leaf = try tree.newLeaf(style: child)

        var rootStyle = Style()
        rootStyle.display = .flex
        rootStyle.size = lengthSize(100, 100)
        rootStyle.justifyContent = AlignContent(keyword: .center, safety: .default)
        rootStyle.alignItems = AlignItems(keyword: .center, safety: .default)
        let root = try tree.newWithChildren(style: rootStyle, children: [leaf])

        try tree.computeLayout(root: root, available: .maxContent)

        #expect(try tree.layout(node: leaf).location == Point(x: 30, y: 30))
    }

    @Test func percentDimensionResolvesAgainstParent() throws {
        let tree = TaffyTree()

        var child = Style()
        child.size = DimensionSize(width: .percent(0.5), height: .length(10))
        let leaf = try tree.newLeaf(style: child)

        var rootStyle = Style()
        rootStyle.display = .flex
        rootStyle.size = lengthSize(200, 100)
        let root = try tree.newWithChildren(style: rootStyle, children: [leaf])

        try tree.computeLayout(root: root, available: .maxContent)

        #expect(try tree.layout(node: leaf).size.width == 100)
    }
}

@Suite("Block")
struct BlockTests {
    @Test func childrenStackVertically() throws {
        let tree = TaffyTree()

        var child = Style()
        child.size = lengthSize(60, 30)
        let a = try tree.newLeaf(style: child)
        let b = try tree.newLeaf(style: child)

        var rootStyle = Style()
        rootStyle.display = .block
        rootStyle.size = lengthSize(100, 100)
        let root = try tree.newWithChildren(style: rootStyle, children: [a, b])

        try tree.computeLayout(root: root, available: .maxContent)

        #expect(try tree.layout(node: a).location == Point(x: 0, y: 0))
        #expect(try tree.layout(node: b).location == Point(x: 0, y: 30))
    }
}

@Suite("Measure")
struct MeasureTests {
    @Test func closureSizesLeafNodes() throws {
        let tree = TaffyTree()
        let text = try tree.newLeaf(style: Style())

        var rootStyle = Style()
        rootStyle.display = .flex
        let root = try tree.newWithChildren(style: rootStyle, children: [text])

        var measured: [NodeId] = []
        try tree.computeLayout(root: root, available: .maxContent) { node, _, _ in
            measured.append(node)
            return Size(width: 40, height: 12)
        }

        #expect(measured.contains(text))
        #expect(try tree.layout(node: text).size == Size(width: 40, height: 12))
        #expect(try tree.layout(node: root).size == Size(width: 40, height: 12))
    }

    @Test func protocolImplementationReceivesAvailableSpace() throws {
        final class Recorder: Measure {
            var sawDefiniteWidth: Float?
            func measure(node: NodeId, known: OptionalSize, available: AvailableSize) -> Size {
                if case .definite(let width) = available.width { sawDefiniteWidth = width }
                return Size(width: 10, height: 10)
            }
        }

        let tree = TaffyTree()
        let leaf = try tree.newLeaf(style: Style())

        let recorder = Recorder()
        try tree.computeLayoutWithMeasure(
            root: leaf, available: .definite(width: 80, height: 60), measure: recorder
        )

        #expect(recorder.sawDefiniteWidth == 80)
        #expect(try tree.layout(node: leaf).size == Size(width: 10, height: 10))
    }

    @Test func styleSizeArrivesAsDefiniteAvailableSpace() throws {
        let tree = TaffyTree()

        var leafStyle = Style()
        leafStyle.size = DimensionSize(width: .length(50), height: .auto)
        let leaf = try tree.newLeaf(style: leafStyle)

        var availableWidth: AvailableSpace?
        try tree.computeLayout(root: leaf, available: .maxContent) { _, _, available in
            availableWidth = available.width
            return Size(width: 999, height: 20)
        }

        #expect(availableWidth == .definite(50))
        #expect(try tree.layout(node: leaf).size == Size(width: 50, height: 20))
    }

    @Test func stretchedCrossAxisIsReportedAsKnown() throws {
        let tree = TaffyTree()
        let leaf = try tree.newLeaf(style: Style())

        var rootStyle = Style()
        rootStyle.display = .flex
        rootStyle.flexDirection = .column
        rootStyle.size = DimensionSize(width: .length(120), height: .auto)
        let root = try tree.newWithChildren(style: rootStyle, children: [leaf])

        var knownWidths: [Float] = []
        try tree.computeLayout(root: root, available: .maxContent) { _, known, _ in
            if let width = known.width { knownWidths.append(width) }
            return Size(width: 30, height: 15)
        }

        #expect(knownWidths.contains(120))
        #expect(try tree.layout(node: leaf).size == Size(width: 120, height: 15))
    }
}

@Suite("Tree")
struct TreeTests {
    @Test func childBookkeeping() throws {
        let tree = TaffyTree()
        let parent = try tree.newLeaf(style: Style())
        let a = try tree.newLeaf(style: Style())
        let b = try tree.newLeaf(style: Style())

        try tree.addChild(parent: parent, child: a)
        try tree.insertChildAtIndex(parent: parent, index: 0, child: b)

        #expect(try tree.children(parent: parent) == [b, a])
        #expect(try tree.childCount(parent: parent) == 2)
        #expect(try tree.childAtIndex(parent: parent, index: 1) == a)
        #expect(tree.parent(child: a) == parent)
        #expect(tree.parent(child: parent) == nil)
        #expect(tree.totalNodeCount() == 3)

        let removed = try tree.removeChildAtIndex(parent: parent, index: 0)
        #expect(removed == b)
        #expect(try tree.children(parent: parent) == [a])

        let c = try tree.newLeaf(style: Style())
        let replaced = try tree.replaceChildAtIndex(parent: parent, index: 0, child: c)
        #expect(replaced == a)
        #expect(try tree.children(parent: parent) == [c])
    }

    @Test func removeAndClear() throws {
        let tree = TaffyTree()
        let node = try tree.newLeaf(style: Style())
        _ = try tree.remove(node: node)
        #expect(tree.totalNodeCount() == 0)

        _ = try tree.newLeaf(style: Style())
        tree.clear()
        #expect(tree.totalNodeCount() == 0)
    }

    @Test func styleRoundTrips() throws {
        let tree = TaffyTree()

        var style = Style()
        style.display = .flex
        style.flexDirection = .columnReverse
        style.flexWrap = .wrapReverse
        style.flexGrow = 2.5
        style.flexBasis = .percent(0.25)
        style.aspectRatio = 1.5
        style.alignSelf = AlignItems(keyword: .flexEnd, safety: .safe)
        style.margin = LengthPercentageAutoRect(left: .auto, right: .length(4), top: .percent(0.1), bottom: .auto)
        style.minSize = LengthPercentageAutoSize(width: .length(10), height: .auto)
        style.overflow = OverflowPoint(x: .scroll, y: .hidden)
        style.contain = Contain(layout: true, paint: false)
        style.float = .right
        style.clear = .both
        style.position = .absolute
        style.size = DimensionSize(width: .fitContentPx(30), height: .stretch)

        let node = try tree.newLeaf(style: style)
        #expect(try tree.style(node: node) == style)

        var changed = style
        changed.display = .block
        try tree.setStyle(node: node, style: changed)
        #expect(try tree.style(node: node) == changed)
    }

    @Test func defaultStyleMatchesTaffy() {
        let style = Style()
        #expect(style.display == .flex)
        #expect(style.flexShrink == 1)
        #expect(style.flexGrow == 0)
        #expect(style.flexDirection == .row)
        #expect(style.size == DimensionSize(width: .auto, height: .auto))
        #expect(style.alignSelf == nil)
        #expect(style.boxSizing == .borderBox)
    }

    @Test func dirtyTracking() throws {
        let tree = TaffyTree()
        let node = try tree.newLeaf(style: Style())
        #expect(try tree.dirty(node: node))
        try tree.computeLayout(root: node, available: .maxContent)
        #expect(try tree.dirty(node: node) == false)
        try tree.markDirty(node: node)
        #expect(try tree.dirty(node: node))
    }

    @Test func roundingCanBeDisabled() throws {
        let tree = TaffyTree()

        var child = Style()
        child.flexGrow = 1
        let leaves = try (0..<3).map { _ in try tree.newLeaf(style: child) }

        var rootStyle = Style()
        rootStyle.display = .flex
        rootStyle.size = lengthSize(100, 10)
        let root = try tree.newWithChildren(style: rootStyle, children: leaves)

        try tree.computeLayout(root: root, available: .maxContent)
        #expect(try tree.layout(node: leaves[0]).size.width == 33)
        #expect(try tree.unroundedLayout(node: leaves[0]).size.width != 33)

        tree.disableRounding()
        try tree.markDirty(node: root)
        try tree.computeLayout(root: root, available: .maxContent)
        let width = try tree.layout(node: leaves[0]).size.width
        #expect(abs(width - 100.0 / 3.0) < 0.01)
    }

    @Test func invalidNodesThrow() throws {
        let tree = TaffyTree()
        let node = try tree.newLeaf(style: Style())
        _ = try tree.remove(node: node)

        #expect(throws: TaffyError.self) { try tree.layout(node: node) }
        #expect(throws: TaffyError.self) { try tree.unroundedLayout(node: node) }
        #expect(throws: TaffyError.self) { try tree.style(node: node) }
        #expect(throws: TaffyError.self) { try tree.computeLayout(root: node, available: .maxContent) }
    }

    @Test func linkingAnAncestorBelowItsDescendantThrows() throws {
        let tree = TaffyTree()
        let a = try tree.newLeaf(style: Style())
        let b = try tree.newLeaf(style: Style())
        try tree.addChild(parent: a, child: b)

        #expect(throws: TaffyError.invalidChildNode) { try tree.addChild(parent: b, child: a) }
        #expect(throws: TaffyError.invalidChildNode) { try tree.addChild(parent: a, child: a) }
        // The tree is still usable afterwards.
        try tree.computeLayout(root: a, available: .maxContent)
    }

    @Test func removedNodesCannotBeLinked() throws {
        let tree = TaffyTree()
        let parent = try tree.newLeaf(style: Style())
        let gone = try tree.newLeaf(style: Style())
        _ = try tree.remove(node: gone)

        #expect(throws: TaffyError.invalidChildNode) { try tree.addChild(parent: parent, child: gone) }
        #expect(throws: TaffyError.invalidParentNode) { try tree.addChild(parent: gone, child: parent) }
        #expect(throws: TaffyError.invalidChildNode) {
            try tree.newWithChildren(style: Style(), children: [gone])
        }
        #expect(tree.parent(child: gone) == nil)
    }

    @Test func childIndexOutOfBoundsThrows() throws {
        let tree = TaffyTree()
        let parent = try tree.newLeaf(style: Style())
        #expect(throws: TaffyError.childIndexOutOfBounds) {
            try tree.removeChildAtIndex(parent: parent, index: 3)
        }
    }

    @Test func treeIsUsableAcrossThreads() async throws {
        let tree = TaffyTree()
        let results = try await withThrowingTaskGroup(of: NodeId.self) { group in
            for _ in 0..<8 {
                group.addTask { try tree.newLeaf(style: Style()) }
            }
            var ids: [NodeId] = []
            for try await id in group { ids.append(id) }
            return ids
        }
        #expect(Set(results).count == 8)
        #expect(tree.totalNodeCount() == 8)
    }
}
