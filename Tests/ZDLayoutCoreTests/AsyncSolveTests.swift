import CoreGraphics
import Testing
@testable import ZDLayoutCore

/// Text of 1300pt on one line, 17pt per line, wrapping at the width it is offered.
private func wrappedSize(_ c: MeasureConstraint) -> CGSize {
    let width = c.knownWidth ?? c.availableWidth.definiteValue ?? (c.availableWidth == .minContent ? 40 : 1300)
    let w = min(max(width, 1), 1300)
    return CGSize(width: w, height: (1300 / w).rounded(.up) * 17)
}

/// Measures somewhere other than the caller, the way a background text engine would.
private actor TextEngine {
    private(set) var questions = 0
    func size(for c: MeasureConstraint) -> CGSize {
        questions += 1
        return wrappedSize(c)
    }
}

@Suite("Async solve")
struct AsyncSolveTests {
    @Test func matchesTheSynchronousSolverForWrappingContent() async throws {
        let sync = Column(gap: 6) {
            Row(alignItems: .start) { Leaf(measure: wrappedSize).grow(1).shrink(1); Leaf().size(40) }.padding(10)
        }
        let async = Column(gap: 6) {
            Row(alignItems: .start) { Leaf(asyncMeasure: { wrappedSize($0) }).grow(1).shrink(1); Leaf().size(40) }.padding(10)
        }
        let proposed = ProposedSize(CGSize(width: 320, height: 600))

        let expected = try LayoutSolver.solve(sync.layoutNode, in: proposed)
        let actual = try await LayoutSolver.solveAsync(async.layoutNode, in: proposed)

        #expect(actual.leaves.map(\.frame) == expected.leaves.map(\.frame))
        #expect(actual.frame == expected.frame)
    }

    @Test func leavesCanBeMeasuredOnAnotherActor() async throws {
        let engine = TextEngine()
        let root = Row(alignItems: .start) {
            Leaf(asyncMeasure: { await engine.size(for: $0) }).grow(1).shrink(1)
        }

        let result = try await LayoutSolver.solveAsync(root.layoutNode, in: ProposedSize(CGSize(width: 200, height: 400)))

        #expect(result.children[0].frame.width == 200)
        #expect(result.children[0].frame.height == (1300 / 200.0).rounded(.up) * 17)
        #expect(await engine.questions > 0)
    }

    @Test func suspendingMeasuresAreAwaited() async throws {
        let root = Row {
            Leaf(asyncMeasure: { _ in
                try? await Task.sleep(nanoseconds: 2_000_000)
                return CGSize(width: 33, height: 11)
            })
        }

        let result = try await LayoutSolver.solveAsync(root.layoutNode, in: .unconstrained)

        #expect(result.children[0].frame.size == CGSize(width: 33, height: 11))
    }

    @Test func synchronousLeavesRunOnTheCallersActor() async throws {
        // A synchronous measure that must stay on the main actor, the way a UIKit view's would.
        let root = Row {
            Leaf { _ in
                MainActor.assumeIsolated { CGSize(width: 12, height: 8) }
            }
        }

        let result = try await onMainActor { try await LayoutSolver.solveAsync(root.layoutNode, in: .unconstrained) }

        #expect(result.children[0].frame.size == CGSize(width: 12, height: 8))
    }

    @Test func asyncAndSyncLeavesMix() async throws {
        let root = Row(gap: 4) {
            Leaf { _ in CGSize(width: 10, height: 10) }
            Leaf(asyncMeasure: { _ in CGSize(width: 20, height: 10) })
        }

        let result = try await LayoutSolver.solveAsync(root.layoutNode, in: .unconstrained)

        #expect(result.children.map(\.frame.width) == [10, 20])
        #expect(result.frame.width == 34)
    }

    @Test func theSynchronousSolverIgnoresAsyncOnlyLeaves() throws {
        let root = Row { Leaf(asyncMeasure: { _ in CGSize(width: 50, height: 50) }) }

        let result = try LayoutSolver.solve(root.layoutNode, in: .unconstrained)

        #expect(result.children[0].frame.size == .zero)
    }

    @Test func guidesAndPixelSnappingSurviveTheAsyncPath() async throws {
        let guide = LayoutGuide()
        let root = Row {
            for _ in 0..<3 { Leaf(asyncMeasure: { _ in CGSize(width: 10, height: 10) }).grow(1) }
        }
        .size(100, 10)
        .guide(guide)
        .layoutNode

        let result = try await LayoutSolver.solveAsync(root, in: ProposedSize(CGSize(width: 100, height: 10)), environment: LayoutEnvironment(scale: 3))
        root.forEach(solvedBy: result) { node, resolved in node.guide?.resolve(resolved.absoluteFrame) }

        #expect(guide.frame == CGRect(x: 0, y: 0, width: 100, height: 10))
        #expect(result.children[0].absoluteFrame.maxX == result.children[1].absoluteFrame.minX)
    }
}

@MainActor
private func onMainActor<T: Sendable>(_ body: @MainActor () async throws -> T) async rethrows -> T {
    try await body()
}
