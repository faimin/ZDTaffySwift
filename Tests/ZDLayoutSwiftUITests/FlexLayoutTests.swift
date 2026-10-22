#if canImport(SwiftUI) && canImport(AppKit)
import AppKit
import SwiftUI
import Testing
import ZDLayoutCore
@testable import ZDLayoutSwiftUI

/// Collects the frame (in the stack's coordinate space) each child reports through a preference.
private struct FramesKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

@MainActor
private final class Frames {
    var values: [Int: CGRect] = [:]
}

private extension View {
    func reportFrame(_ id: Int) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: FramesKey.self, value: [id: proxy.frame(in: .named("stack"))])
        })
    }
}

/// Hosts `content` in a window-less `NSHostingView`, lets SwiftUI run a few layout passes, and returns the frames.
@MainActor
private func layOut<Content: View>(width: CGFloat, height: CGFloat, @ViewBuilder _ content: () -> Content) -> [Int: CGRect] {
    let frames = Frames()
    let host = NSHostingView(rootView:
        content()
            .coordinateSpace(name: "stack")
            .onPreferenceChange(FramesKey.self) { frames.values = $0 }
    )
    host.frame = CGRect(x: 0, y: 0, width: width, height: height)
    for _ in 0..<6 {
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    return frames.values
}

@MainActor
@Suite("FlexStack")
struct FlexStackTests {
    @Test func growSharesTheRemainingWidth() {
        let frames = layOut(width: 200, height: 50) {
            FlexStack(.row) {
                Color.red.frame(idealWidth: 40, idealHeight: 20).reportFrame(0)
                Color.green.frame(idealWidth: 10, idealHeight: 20).flexItem(grow: 1).reportFrame(1)
            }
        }

        #expect(frames[1]?.width == 160)
        #expect(frames[1]?.minX == 40)
        #expect(frames[0]?.minX == 0)
    }

    @Test func gapAndPaddingAreApplied() {
        let frames = layOut(width: 200, height: 200) {
            FlexStack(.column, gap: 10, padding: Edges(8)) {
                Color.red.frame(idealWidth: 50, idealHeight: 20).reportFrame(0)
                Color.green.frame(idealWidth: 50, idealHeight: 30).reportFrame(1)
            }
        }

        #expect(frames[0]?.minY == 8)
        #expect(frames[0]?.minX == 8)
        #expect(frames[1]?.minY == 38)
    }

    @Test func textWrapsToTheWidthItIsGiven() {
        let frames = layOut(width: 120, height: 400) {
            FlexStack(.row, alignItems: .start) {
                Color.red.frame(width: 30, height: 30).reportFrame(0)
                Text("The quick brown fox jumps over the lazy dog").flexItem(grow: 1, shrink: 1).reportFrame(1)
            }
        }

        #expect(frames[1]?.minX == 30)
        #expect((frames[1]?.width ?? 0) <= 90)
        #expect((frames[1]?.height ?? 0) > 30)
    }

    @Test func hiddenChildrenTakeNoSpace() {
        let frames = layOut(width: 200, height: 50) {
            FlexStack(.row, gap: 10) {
                Color.red.frame(width: 30, height: 20).reportFrame(0)
                Color.green.frame(width: 30, height: 20).flexItem { $0.isHidden = true }.reportFrame(1)
                Color.blue.frame(width: 30, height: 20).reportFrame(2)
            }
        }

        #expect(frames[2]?.minX == 40)
    }

    @Test func gridTracksAndPlacement() {
        let frames = layOut(width: 200, height: 100) {
            FlexStack(columns: [.fr(1), .fr(3)], rows: [.fixed(30), .fixed(30)]) {
                Color.red.reportFrame(0)
                Color.green.reportFrame(1)
                Color.blue.gridItem(column: .line(1, span: 2)).reportFrame(2)
            }
        }

        #expect(frames[0] == CGRect(x: 0, y: 0, width: 50, height: 30))
        #expect(frames[1] == CGRect(x: 50, y: 0, width: 150, height: 30))
        #expect(frames[2] == CGRect(x: 0, y: 30, width: 200, height: 30))
    }

    @Test func rightToLeftMirrorsTheRow() {
        let frames = layOut(width: 200, height: 50) {
            FlexStack(.row, padding: Edges(leading: 20)) {
                Color.red.frame(width: 30, height: 20).reportFrame(0)
                Color.clear.flexItem(grow: 1)
                Color.green.frame(width: 30, height: 20).reportFrame(2)
            }
            .environment(\.layoutDirection, .rightToLeft)
        }

        // The first child sits at the right edge, after the leading (right-hand) padding.
        #expect(frames[0]?.maxX == 180)
        #expect(frames[2]?.minX == 0)
    }

    @Test func theStackReportsItsContentSize() {
        let host = NSHostingView(rootView:
            FlexStack(.row, gap: 10, padding: Edges(5)) {
                Color.red.frame(width: 30, height: 20)
                Color.green.frame(width: 40, height: 50)
            }
        )

        let size = host.fittingSize

        #expect(size == CGSize(width: 5 + 30 + 10 + 40 + 5, height: 5 + 50 + 5))
    }
}
#endif
