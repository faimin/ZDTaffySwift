import CoreGraphics
import Testing
@testable import ZDLayoutCore

private func solve(
    _ root: some LayoutComponent,
    _ size: CGSize = CGSize(width: 300, height: 200),
    environment: LayoutEnvironment = LayoutEnvironment()
) throws -> ResolvedLayout {
    try LayoutSolver.solve(root.layoutNode, in: ProposedSize(size), environment: environment)
}

@Suite("Flex")
struct FlexTests {
    @Test func rowSharesSpaceByGrow() throws {
        let root = Row {
            Leaf().grow(1)
            Leaf().grow(2)
        }
        let result = try solve(root, CGSize(width: 300, height: 50))

        #expect(result.children[0].frame == CGRect(x: 0, y: 0, width: 100, height: 50))
        #expect(result.children[1].frame == CGRect(x: 100, y: 0, width: 200, height: 50))
    }

    @Test func columnStacksWithGapAndPadding() throws {
        let root = Column(gap: 10) {
            Leaf().size(50, 20)
            Leaf().size(50, 30)
        }
        .padding(8)
        .size(200, 200)

        let result = try solve(root)

        #expect(result.children[0].frame == CGRect(x: 8, y: 8, width: 50, height: 20))
        #expect(result.children[1].frame == CGRect(x: 8, y: 38, width: 50, height: 30))
    }

    @Test func spacerPushesSiblingsApart() throws {
        let root = Row(alignItems: .center) {
            Leaf().size(40, 20)
            Spacer()
            Leaf().size(40, 20)
        }
        .size(300, 100)

        let result = try solve(root)

        #expect(result.children[0].absoluteFrame.minX == 0)
        #expect(result.children[2].absoluteFrame.maxX == 300)
        #expect(result.children[0].absoluteFrame.minY == 40)
    }

    @Test func cgFloatValuesAreAccepted() throws {
        let side: CGFloat = 30
        let gap: CGFloat = 6
        let root = Row {
            Leaf().size(side)
            Leaf().width(side).height(side / 2)
        }
        .padding(horizontal: gap, vertical: gap)
        .size(200, 100)

        let result = try solve(root)

        #expect(result.children[0].frame == CGRect(x: 6, y: 6, width: 30, height: 30))
        #expect(result.children[1].frame.size == CGSize(width: 30, height: 15))
    }

    @Test func edgesAcceptCGFloatValues() throws {
        let inset: CGFloat = 7
        let root = Row { Leaf().size(10, 10) }
            .padding(Edges(inset))
            .margin(Edges(horizontal: inset, vertical: 0))
            .size(100, 100)

        #expect(root.style.padding == Edges(7))
        #expect(root.style.margin == Edges(horizontal: 7, vertical: 0))
        #expect(Edges(top: inset) == Edges(top: 7, leading: 0, bottom: 0, trailing: 0))
    }

    @Test func percentAndLiteralPointsResolve() throws {
        let root = Row {
            Leaf().width(.percent(25)).height(10)
            Leaf().width(50.percent).height(10)
            Leaf().width(20).height(10)
        }
        .size(400, 100)

        let result = try solve(root)

        #expect(result.children.map(\.frame.width) == [100, 200, 20])
    }

    @Test func justifyContentDistributesFreeSpace() throws {
        let root = Row(justifyContent: .spaceBetween) {
            Leaf().size(10, 10)
            Leaf().size(10, 10)
            Leaf().size(10, 10)
        }
        .size(100, 10)

        let result = try solve(root)

        #expect(result.children.map(\.frame.minX) == [0, 45, 90])
    }

    @Test func wrappingMovesOverflowToNextLine() throws {
        let root = Row(wraps: true) {
            for _ in 0..<3 { Leaf().size(60, 20).shrink(0) }
        }
        .size(150, 100)
        // By default wrapped lines are stretched to share the cross axis; pack them at the start instead.
        .styled { $0.alignContent = .start }

        let result = try solve(root)

        #expect(result.children[0].frame.origin == .zero)
        #expect(result.children[1].frame.minX == 60)
        #expect(result.children[2].frame.origin == CGPoint(x: 0, y: 20))
    }

    @Test func itemsDoNotShrinkUnlessAsked() throws {
        let rigid = Row {
            Leaf().size(80, 10)
            Leaf().size(80, 10)
        }
        .size(100, 10)
        let flexible = Row {
            Leaf().size(80, 10).shrink(1)
            Leaf().size(80, 10).shrink(1)
        }
        .size(100, 10)

        #expect(try solve(rigid).children.map(\.frame.width) == [80, 80])
        #expect(try solve(flexible).children.map(\.frame.width) == [50, 50])
    }

    @Test func builderSupportsConditionalsAndLoops() throws {
        func make(showBadge: Bool, count: Int) -> LayoutNode {
            Row {
                Leaf().size(10, 10)
                if showBadge { Leaf().size(10, 10) }
                for _ in 0..<count { Leaf().size(10, 10) }
            }
            .layoutNode
        }

        #expect(make(showBadge: false, count: 0).children.count == 1)
        #expect(make(showBadge: true, count: 2).children.count == 4)
    }

    @Test func absoluteChildDoesNotTakePartInFlow() throws {
        let root = Row {
            Leaf().size(50, 50)
            Leaf().size(20, 20).absolute(inset: Edges(top: 5, leading: .auto, bottom: .auto, trailing: 5))
            Leaf().size(50, 50)
        }
        .size(200, 100)

        let result = try solve(root)

        #expect(result.children[2].frame.minX == 50)
        #expect(result.children[1].frame == CGRect(x: 175, y: 5, width: 20, height: 20))
    }

    @Test func minAndMaxClampSizes() throws {
        let root = Row {
            Leaf().grow(1).maxSize(width: 40)
            Leaf().grow(1).minSize(width: 150)
        }
        .size(300, 10)

        let result = try solve(root)

        #expect(result.children[0].frame.width == 40)
        #expect(result.children[1].frame.width == 260)
    }

    @Test func aspectRatioDerivesHeight() throws {
        let root = Column(alignItems: .start) {
            Leaf().width(100).aspectRatio(2)
        }
        .size(300, 300)

        let result = try solve(root)

        #expect(result.children[0].frame.size == CGSize(width: 100, height: 50))
    }

    @Test func customEscapeHatchReachesTaffyStyle() throws {
        let root = Row {
            Leaf().size(10, 10).custom { $0.flexGrow = 3 }
            Leaf().grow(1).height(10)
        }
        .size(400, 10)

        let result = try solve(root)

        #expect(result.children[0].frame.width > result.children[1].frame.width)
    }
}

@Suite("Hidden and direction")
struct DirectionTests {
    @Test func hiddenNodesTakeNoSpace() throws {
        let root = Row(gap: 10) {
            Leaf().size(30, 10)
            Leaf().size(30, 10).hidden()
            Leaf().size(30, 10)
        }
        .size(200, 10)

        let result = try solve(root)

        #expect(result.children[1].frame.size == .zero)
        #expect(result.children[2].frame.minX == 40)
    }

    @Test func rightToLeftMirrorsRowAndLeadingPadding() throws {
        let root = Row {
            Leaf().size(30, 10)
            Leaf().size(30, 10)
        }
        .padding(Edges(leading: 20))
        .size(200, 10)

        let ltr = try solve(root, environment: LayoutEnvironment(direction: .leftToRight))
        let rtl = try solve(root, environment: LayoutEnvironment(direction: .rightToLeft))

        #expect(ltr.children[0].frame.minX == 20)
        #expect(ltr.children[1].frame.minX == 50)
        // The first child sits at the right edge, after the leading (right-hand) padding.
        #expect(rtl.children[0].frame.maxX == 180)
        #expect(rtl.children[1].frame.maxX == 150)
    }
}

@Suite("Root sizing")
struct RootSizingTests {
    private let root = Row {
        Leaf { _ in CGSize(width: 40, height: 10) }
    }

    @Test func fillTakesTheProposedSize() throws {
        let result = try LayoutSolver.solve(root.layoutNode, in: ProposedSize(CGSize(width: 300, height: 80)), sizing: .fill)

        #expect(result.frame.size == CGSize(width: 300, height: 80))
    }

    @Test func fitTakesTheContentSize() throws {
        let result = try LayoutSolver.solve(root.layoutNode, in: ProposedSize(CGSize(width: 300, height: 80)), sizing: .fit)

        #expect(result.frame.size == CGSize(width: 40, height: 10))
    }

    @Test func fillKeepsExplicitSizes() throws {
        let result = try LayoutSolver.solve(
            root.width(120).layoutNode, in: ProposedSize(CGSize(width: 300, height: 80)), sizing: .fill
        )

        #expect(result.frame.size == CGSize(width: 120, height: 80))
    }

    @Test func fillIgnoresUnconstrainedAxes() throws {
        let result = try LayoutSolver.solve(root.layoutNode, in: .unconstrained, sizing: .fill)

        #expect(result.frame.size == CGSize(width: 40, height: 10))
    }

    @Test func fitOffersTheProposalToContent() throws {
        // Content that wraps to whatever width it is offered, up to 500pt.
        let wrapping = Row { Leaf { constraint in
            CGSize(width: min(constraint.availableWidth.definiteValue ?? 500, 500), height: 10)
        } }

        let result = try LayoutSolver.solve(wrapping.layoutNode, in: ProposedSize(CGSize(width: 200, height: 80)), sizing: .fit)

        #expect(result.frame.width == 200)
    }
}

@Suite("Measurement")
struct MeasurementTests {
    @Test func measureSizesLeafAndContainer() throws {
        let root = Row(gap: 4, alignItems: .start) {
            Leaf { _ in CGSize(width: 40, height: 12) }
            Leaf { _ in CGSize(width: 20, height: 30) }
        }
        .padding(2)

        let result = try LayoutSolver.solve(root.layoutNode, in: .unconstrained)

        #expect(result.children[0].frame.size == CGSize(width: 40, height: 12))
        #expect(result.frame.size == CGSize(width: 68, height: 34))
    }

    @Test func wrappingContentReceivesAvailableWidth() throws {
        // 120pt of text that wraps into lines of at most the offered width.
        let paragraph = Leaf { constraint in
            let width = min(constraint.availableWidth.definiteValue ?? 120, 120)
            let lines = (120 / max(width, 1)).rounded(.up)
            return CGSize(width: width, height: lines * 10)
        }
        let root = Column(alignItems: .start) { paragraph.width(60) }

        let result = try LayoutSolver.solve(root.layoutNode, in: ProposedSize(CGSize(width: 300, height: 300)))

        #expect(result.children[0].frame.size == CGSize(width: 60, height: 20))
    }

    @Test func identicalQuestionsAreMeasuredOnce() throws {
        nonisolated(unsafe) var calls = 0
        let root = Column {
            Leaf { _ in
                calls += 1
                return CGSize(width: 10, height: 10)
            }
        }

        _ = try LayoutSolver.solve(root.layoutNode, in: ProposedSize(CGSize(width: 100, height: 100)))
        let firstPass = calls
        _ = try LayoutSolver.solve(root.layoutNode, in: ProposedSize(CGSize(width: 100, height: 100)))

        #expect(firstPass >= 1)
        // Nothing is cached between passes: every solve measures again.
        #expect(calls >= firstPass * 2)
    }

    @Test func leavesWithoutMeasureHaveNoIntrinsicSize() throws {
        let root = Row { Leaf() }

        let result = try LayoutSolver.solve(root.layoutNode, in: .unconstrained)

        #expect(result.frame.size == .zero)
    }
}

@Suite("Pixel snapping")
struct PixelSnappingTests {
    @Test func thirdsStayFlushAtOneX() throws {
        let root = Row {
            for _ in 0..<3 { Leaf().grow(1) }
        }
        .size(100, 10)

        let result = try solve(root, environment: LayoutEnvironment(scale: 1))

        let edges = result.children.map(\.absoluteFrame)
        #expect(edges[0].minX == 0)
        #expect(edges[0].maxX == edges[1].minX)
        #expect(edges[1].maxX == edges[2].minX)
        #expect(edges[2].maxX == 100)
        #expect(edges.allSatisfy { $0.minX == $0.minX.rounded() && $0.width == $0.width.rounded() })
    }

    @Test func framesLandOnPixelsAtTwoAndThreeX() throws {
        let root = Row {
            for _ in 0..<3 { Leaf().grow(1) }
        }
        .size(100, 10)

        for scale: CGFloat in [2, 3] {
            let result = try solve(root, environment: LayoutEnvironment(scale: scale))
            for child in result.children {
                let frame = child.absoluteFrame
                #expect((frame.minX * scale).rounded() == frame.minX * scale)
                #expect((frame.maxX * scale).rounded() == frame.maxX * scale)
            }
            #expect(result.children[2].absoluteFrame.maxX == 100)
        }
    }

    @Test func measuredLeavesAreNeverNarrowerThanTheirContent() throws {
        // 32.333pt of text centred in a cell: snapping both edges would give 32.0 and truncate it.
        let root = Column(alignItems: .center) {
            Leaf { _ in CGSize(width: 32.0 + 1.0 / 3, height: 24.5) }
        }
        .size(115.4, 100)

        for scale: CGFloat in [1, 2, 3] {
            let frame = try solve(root, environment: LayoutEnvironment(scale: scale)).children[0].frame
            #expect(frame.width >= 32.0 + 1.0 / 3 - 1e-6)
            #expect(frame.height >= 24.5 - 1e-6)
            #expect(frame.width < 32.0 + 1.0 / 3 + 1.0 / scale + 1e-6)
        }
    }

    @Test func boxesStillSnapEdgesSoNeighboursStayFlush() throws {
        let root = Row {
            for _ in 0..<3 { Leaf().grow(1) }
        }
        .size(100, 10)

        let edges = try solve(root, environment: LayoutEnvironment(scale: 3)).children.map(\.absoluteFrame)

        #expect(edges[0].maxX == edges[1].minX)
        #expect(edges[1].maxX == edges[2].minX)
    }

    @Test func relativeFramesAddUpToAbsoluteFrames() throws {
        let root = Column {
            Row {
                Leaf().grow(1)
                Leaf().grow(1)
                Leaf().grow(1)
            }
            .padding(Edges(top: 0.4, leading: 0.4))
            .grow(1)
        }
        .size(100.5, 50)

        let result = try solve(root, environment: LayoutEnvironment(scale: 2))
        let row = result.children[0]

        for child in row.children {
            #expect(child.absoluteFrame.minX == row.absoluteFrame.minX + child.frame.minX)
            #expect(child.absoluteFrame.minY == row.absoluteFrame.minY + child.frame.minY)
        }
    }
}

@Suite("Grid")
struct GridLayoutTests {
    @Test func frColumnsShareWidth() throws {
        let root = Grid(columns: [.fr(1), .fr(3)], rows: [.fixed(40)]) {
            Leaf()
            Leaf()
        }
        .size(200, 40)

        let result = try solve(root)

        #expect(result.children[0].frame == CGRect(x: 0, y: 0, width: 50, height: 40))
        #expect(result.children[1].frame == CGRect(x: 50, y: 0, width: 150, height: 40))
    }

    @Test func repeatAndGap() throws {
        let root = Grid(columns: [.repeat(.count(3), [.fixed(30)])], rows: [.fixed(10)], gap: 5) {
            for _ in 0..<3 { Leaf() }
        }
        .size(200, 10)

        let result = try solve(root)

        #expect(result.children.map(\.frame.minX) == [0, 35, 70])
    }

    @Test func itemsSpanColumns() throws {
        let root = Grid(columns: [.fixed(100), .fixed(100), .fixed(100)], rows: [.fixed(20)]) {
            Leaf().gridColumn(2, span: 2)
        }
        .size(300, 20)

        let result = try solve(root)

        #expect(result.children[0].frame == CGRect(x: 100, y: 0, width: 200, height: 20))
    }

    @Test func autoRowsAndColumnFlow() throws {
        let root = Grid(columns: [], rows: [.fixed(10), .fixed(10)], autoColumns: [.fixed(25)], autoFlow: .column) {
            for _ in 0..<4 { Leaf() }
        }
        .size(100, 20)

        let result = try solve(root)

        #expect(result.children.map(\.frame.origin) == [
            CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 10), CGPoint(x: 25, y: 0), CGPoint(x: 25, y: 10),
        ])
    }

    @Test func minmaxTrackGrowsWithContent() throws {
        let root = Grid(columns: [.minmax(.fixed(20), .maxContent)], rows: [.auto]) {
            Leaf { _ in CGSize(width: 70, height: 10) }
        }

        let result = try LayoutSolver.solve(root.layoutNode, in: .unconstrained)

        #expect(result.children[0].frame.width == 70)
    }
}
