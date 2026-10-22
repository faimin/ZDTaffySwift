// Run with: swift run -c release ZDLayoutBench
import CoreGraphics
import Foundation
import ZDLayoutCore

/// A list of `rows` rows, each `icon | title (wraps) | Spacer | badge`, which is what a feed or settings page is.
func makeList(rows: Int, measured: Bool) -> LayoutNode {
    Column(gap: 8) {
        for index in 0..<rows {
            Row(gap: 12, alignItems: .center) {
                Leaf().size(40)
                Leaf { constraint in
                    // Roughly a wrapping label: 18pt lines of 600pt of text.
                    let width = constraint.knownWidth ?? constraint.availableWidth.definiteValue ?? 600
                    let w = min(max(width, 1), 600)
                    return CGSize(width: w, height: (600 / w).rounded(.up) * 18)
                }
                .grow(1).shrink(1)
                Spacer()
                Leaf { _ in CGSize(width: 24 + CGFloat(index % 3) * 4, height: 16) }
            }
            .padding(12)
        }
    }
    .layoutNode
}

func time(_ iterations: Int, warmup: Int = 3, _ body: () throws -> Void) rethrows -> (median: Double, min: Double) {
    for _ in 0..<warmup { try body() }
    var samples: [Double] = []
    for _ in 0..<iterations {
        let start = ContinuousClock.now
        try body()
        let elapsed = ContinuousClock.now - start
        samples.append(Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)
    }
    samples.sort()
    return (samples[samples.count / 2], samples[0])
}

func format(_ value: Double) -> String { String(format: "%8.2f", value) }

print("rows  nodes  build+solve(ms, median)  min(ms)   per-node(us)")
for rows in [10, 50, 100, 250, 500, 1000] {
    let list = makeList(rows: rows, measured: true)
    let nodes = rows * 5 + 1
    let result = try time(rows >= 500 ? 10 : 30) {
        _ = try LayoutSolver.solve(list, in: ProposedSize(CGSize(width: 390, height: 844)), sizing: .fill, environment: LayoutEnvironment(scale: 3))
    }
    print(String(format: "%4d  %5d  ", rows, nodes) + format(result.median) + "                " + format(result.min) + "  " + format(result.median * 1000 / Double(nodes)))
}

// MARK: - Where does the time go?

import ZDTaffy

print("\nFFI cost per call (5000 calls each, microseconds)")
let n = 5000
func perCall(_ label: String, _ body: () throws -> Void) rethrows {
    let r = try time(5, warmup: 1, body)
    print("  " + label.padding(toLength: 34, withPad: " ", startingAt: 0) + String(format: "%8.2f", r.median * 1000 / Double(n)))
}

try perCall("Style()  (defaultStyle() FFI)") { for _ in 0..<n { _ = Style() } }
let base = Style()
try perCall("Style copy + 3 field edits") {
    for _ in 0..<n { var s = base; s.flexGrow = 1; s.size = DimensionSize(width: .length(40), height: .auto); s.display = .flex }
}
let tree = TaffyTree()
var ids: [NodeId] = []
try perCall("tree.newLeaf(style:)") { ids = []; for _ in 0..<n { ids.append(try tree.newLeaf(style: base)) } }
try perCall("tree.layout(node:)") { for id in ids { _ = try tree.layout(node: id) } }
let parent = try tree.newWithChildren(style: base, children: Array(ids.prefix(1000)))
try perCall("computeLayout (1000 children, /5000)") { try tree.computeLayout(root: parent, available: AvailableSize(width: .definite(390), height: .maxContent)) }

