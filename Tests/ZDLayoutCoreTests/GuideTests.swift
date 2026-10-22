import CoreGraphics
import Testing
@testable import ZDLayoutCore

@Suite("Layout guides")
struct GuideTests {
    @Test func guidesLearnWhereTheirContainerLanded() throws {
        let rowGuide = LayoutGuide()
        let columnGuide = LayoutGuide()
        let root = Column(gap: 10) {
            Row {
                Leaf().size(30, 20)
                Leaf().size(30, 20)
            }
            .guide(rowGuide)
            Column {
                Leaf().size(50, 40)
            }
            .guide(columnGuide)
        }
        .padding(5)
        .size(200, 200)
        .layoutNode

        let result = try LayoutSolver.solve(root, in: ProposedSize(CGSize(width: 200, height: 200)))
        root.forEach(solvedBy: result) { node, resolved in
            node.guide?.resolve(resolved.absoluteFrame)
        }

        // The Row is stretched across the column, the inner Column is as wide as its content (cross axis start).
        #expect(rowGuide.frame == CGRect(x: 5, y: 5, width: 190, height: 20))
        #expect(columnGuide.frame.origin == CGPoint(x: 5, y: 35))
        #expect(columnGuide.frame.height == 40)
    }

    @Test func traversalVisitsParentsBeforeChildren() throws {
        let root = Column { Row { Leaf() }; Leaf() }.layoutNode
        let result = try LayoutSolver.solve(root, in: .unconstrained)

        nonisolated(unsafe) var depths: [Int] = []
        root.forEach(solvedBy: result) { node, _ in depths.append(node.children.count) }

        #expect(depths == [2, 1, 0, 0])
    }

    @Test func guideModifierKeepsTheRestOfTheNode() {
        let guide = LayoutGuide()
        let node = Row { Leaf() }.width(100).guide(guide)

        #expect(node.guide === guide)
        #expect(node.style.width == .points(100))
        #expect(node.children.count == 1)
    }
}
