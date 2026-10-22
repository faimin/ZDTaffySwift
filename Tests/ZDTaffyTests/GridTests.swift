import Testing
@testable import ZDTaffy

private func px(_ value: Float) -> TrackSizingFunction {
    TrackSizingFunction(min: .length(value), max: .length(value))
}

private func fr(_ value: Float) -> TrackSizingFunction {
    TrackSizingFunction(min: .auto, max: .fr(value))
}

private func sized(_ width: Float, _ height: Float) -> DimensionSize {
    DimensionSize(width: .length(width), height: .length(height))
}

@Suite("Grid")
struct GridTests {
    @Test func frColumnsShareWidth() throws {
        let tree = TaffyTree()
        let a = try tree.newLeaf(style: Style())
        let b = try tree.newLeaf(style: Style())

        var rootStyle = Style()
        rootStyle.display = .grid
        rootStyle.size = sized(200, 100)
        rootStyle.gridTemplateColumns = [.single(fr(1)), .single(fr(3))]
        rootStyle.gridTemplateRows = [.single(px(40))]
        let root = try tree.newWithChildren(style: rootStyle, children: [a, b])

        try tree.computeLayout(root: root, available: .maxContent)

        #expect(try tree.layout(node: a).size == Size(width: 50, height: 40))
        #expect(try tree.layout(node: b).location == Point(x: 50, y: 0))
        #expect(try tree.layout(node: b).size == Size(width: 150, height: 40))
    }

    @Test func repeatExpandsTracks() throws {
        let tree = TaffyTree()
        let children = try (0..<3).map { _ in try tree.newLeaf(style: Style()) }

        var rootStyle = Style()
        rootStyle.display = .grid
        rootStyle.size = sized(300, 100)
        rootStyle.gridTemplateColumns = [
            .repeat(GridTemplateRepetition(count: .count(3), tracks: [px(30)], lineNames: [[], []]))
        ]
        rootStyle.gridTemplateRows = [.single(px(10))]
        let root = try tree.newWithChildren(style: rootStyle, children: children)

        try tree.computeLayout(root: root, available: .maxContent)

        let xs = try children.map { try tree.layout(node: $0).location.x }
        #expect(xs == [0, 30, 60])
    }

    @Test func gapSeparatesTracks() throws {
        let tree = TaffyTree()
        let a = try tree.newLeaf(style: Style())
        let b = try tree.newLeaf(style: Style())

        var rootStyle = Style()
        rootStyle.display = .grid
        rootStyle.size = sized(100, 50)
        rootStyle.gridTemplateColumns = [.single(px(40)), .single(px(40))]
        rootStyle.gridTemplateRows = [.single(px(20))]
        rootStyle.gap = LengthPercentageSize(width: .length(10), height: .length(0))
        let root = try tree.newWithChildren(style: rootStyle, children: [a, b])

        try tree.computeLayout(root: root, available: .maxContent)

        #expect(try tree.layout(node: b).location.x == 50)
    }

    @Test func explicitLineAndSpanPlacement() throws {
        let tree = TaffyTree()

        var itemStyle = Style()
        itemStyle.gridColumn = GridPlacementLine(start: .line(2), end: .span(2))
        itemStyle.gridRow = GridPlacementLine(start: .line(1), end: .auto)
        let item = try tree.newLeaf(style: itemStyle)

        var rootStyle = Style()
        rootStyle.display = .grid
        rootStyle.size = sized(300, 100)
        rootStyle.gridTemplateColumns = [.single(px(100)), .single(px(100)), .single(px(100))]
        rootStyle.gridTemplateRows = [.single(px(100))]
        let root = try tree.newWithChildren(style: rootStyle, children: [item])

        try tree.computeLayout(root: root, available: .maxContent)

        let layout = try tree.layout(node: item)
        #expect(layout.location.x == 100)
        #expect(layout.size.width == 200)
    }

    @Test func templateAreasWithNamedPlacement() throws {
        let tree = TaffyTree()

        var headerStyle = Style()
        headerStyle.gridRow = GridPlacementLine(start: .namedLine(name: "header-start", index: 1), end: .namedLine(name: "header-end", index: 1))
        headerStyle.gridColumn = GridPlacementLine(start: .line(1), end: .line(-1))
        let header = try tree.newLeaf(style: headerStyle)

        var rootStyle = Style()
        rootStyle.display = .grid
        rootStyle.size = sized(100, 100)
        rootStyle.gridTemplateColumns = [.single(fr(1))]
        rootStyle.gridTemplateRows = [.single(px(30)), .single(fr(1))]
        rootStyle.gridTemplateAreas = GridTemplateAreas(
            areas: [GridTemplateArea(name: "header", rowStart: 1, rowEnd: 2, columnStart: 1, columnEnd: 2)],
            rowCount: 2,
            columnCount: 1
        )
        let root = try tree.newWithChildren(style: rootStyle, children: [header])

        try tree.computeLayout(root: root, available: .maxContent)

        let layout = try tree.layout(node: header)
        #expect(layout.location == Point(x: 0, y: 0))
        #expect(layout.size == Size(width: 100, height: 30))
    }

    @Test func autoRowsAndFlowColumn() throws {
        let tree = TaffyTree()
        let children = try (0..<4).map { _ in try tree.newLeaf(style: Style()) }

        var rootStyle = Style()
        rootStyle.display = .grid
        rootStyle.size = sized(100, 100)
        rootStyle.gridAutoFlow = .column
        rootStyle.gridTemplateRows = [.single(px(10)), .single(px(10))]
        rootStyle.gridAutoColumns = [px(25)]
        let root = try tree.newWithChildren(style: rootStyle, children: children)

        try tree.computeLayout(root: root, available: .maxContent)

        let locations = try children.map { try tree.layout(node: $0).location }
        #expect(locations == [
            Point(x: 0, y: 0), Point(x: 0, y: 10),
            Point(x: 25, y: 0), Point(x: 25, y: 10),
        ])
    }

    @Test func gridStyleRoundTrips() throws {
        let tree = TaffyTree()

        var style = Style()
        style.display = .grid
        style.gridTemplateColumns = [
            .single(TrackSizingFunction(min: .minContent, max: .fitContentPx(80))),
            .repeat(GridTemplateRepetition(
                count: .autoFill,
                tracks: [TrackSizingFunction(min: .length(20), max: .fr(2))],
                lineNames: [["a"], ["b"]]
            )),
        ]
        style.gridTemplateRows = [.single(TrackSizingFunction(min: .percent(0.2), max: .maxContent))]
        style.gridAutoRows = [px(5), fr(1)]
        style.gridAutoColumns = [TrackSizingFunction(min: .auto, max: .fitContentPercent(0.5))]
        style.gridAutoFlow = .rowDense
        style.gridTemplateColumnNames = [["start"], ["end"]]
        style.gridTemplateRowNames = [["top"]]
        style.gridRow = GridPlacementLine(start: .namedSpan(name: "x", count: 2), end: .auto)
        style.gridColumn = GridPlacementLine(start: .line(-2), end: .span(3))

        let node = try tree.newLeaf(style: style)
        #expect(try tree.style(node: node) == style)
    }

    @Test func defaultGridPropertiesAreEmpty() {
        let style = Style()
        #expect(style.gridTemplateColumns.isEmpty)
        #expect(style.gridTemplateRows.isEmpty)
        #expect(style.gridTemplateAreas == nil)
        #expect(style.gridAutoFlow == .row)
        #expect(style.gridRow == GridPlacementLine(start: .auto, end: .auto))
    }
}
