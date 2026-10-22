#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
import Testing
import ZDLayoutCore
@testable import ZDLayoutAppKit

@MainActor
private func fixed() -> NSView {
    let view = NSView()
    view.wantsLayer = true
    return view
}

@MainActor
private func layOut(_ view: NSView, width: CGFloat, height: CGFloat) {
    view.frame = CGRect(x: 0, y: 0, width: width, height: height)
    view.needsLayout = true
    view.layoutSubtreeIfNeeded()
}

@MainActor
@Suite("AppKit FlexView")
struct AppKitFlexViewTests {
    @Test func positionsSubviewsFromTheTopLeft() {
        let a = fixed(), b = fixed()
        let view = FlexView {
            Row(gap: 10) { a.size(40, 20); b.size(30, 20) }
        }
        layOut(view, width: 200, height: 100)

        #expect(view.isFlipped)
        #expect(a.superview === view)
        #expect(a.frame == CGRect(x: 0, y: 0, width: 40, height: 20))
        #expect(b.frame == CGRect(x: 50, y: 0, width: 30, height: 20))
    }

    @Test func growFillsTheRemainingSpace() {
        let a = fixed(), b = fixed()
        let view = FlexView { Row { a.size(40, 20); b.height(20).grow(1) } }
        layOut(view, width: 200, height: 50)

        #expect(b.frame == CGRect(x: 40, y: 0, width: 160, height: 20))
    }

    @Test func descriptionIsReEvaluatedEveryPass() {
        let a = fixed(), b = fixed()
        nonisolated(unsafe) var showsB = true
        let view = FlexView { Row { a.size(10, 10); if showsB { b.size(10, 10) } } }
        layOut(view, width: 100, height: 50)
        #expect(b.superview === view)

        showsB = false
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        #expect(b.superview == nil)
        #expect(a.superview === view)
    }

    @Test func hiddenViewsTakeNoSpace() {
        let a = fixed(), b = fixed(), c = fixed()
        let view = FlexView { Row(gap: 10) { a.size(30, 10); b.size(30, 10); c.size(30, 10) } }
        b.isHidden = true
        layOut(view, width: 200, height: 20)

        #expect(c.frame.minX == 40)
    }

    @Test func rightToLeftMirrorsTheRow() {
        let a = fixed(), b = fixed()
        let view = FlexView { Row { a.size(30, 10); b.size(30, 10) }.padding(Edges(leading: 20)) }
        view.userInterfaceLayoutDirection = .rightToLeft
        layOut(view, width: 200, height: 20)

        #expect(a.frame.maxX == 180)
        #expect(b.frame.maxX == 150)
    }

    @Test func wrappingTextFieldsFitTheWidthTheyAreGiven() {
        let field = NSTextField(wrappingLabelWithString: "The quick brown fox jumps over the lazy dog")
        let icon = fixed()
        let view = FlexView { Row(gap: 8, alignItems: .start) { icon.size(40); field.shrink(1) } }
        layOut(view, width: 160, height: 300)

        #expect(field.frame.maxX <= 160)
        #expect(field.frame.height > NSTextField(labelWithString: "x").intrinsicContentSize.height * 1.5)
    }

    @Test func aTruncatingFieldCanShrinkNextToOtherViews() {
        let field = NSTextField(labelWithString: "A very long title that cannot possibly fit in a narrow window")
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        let icon = fixed()
        let view = FlexView { Row(gap: 8) { icon.size(40); field.grow(1).shrink(1) } }
        layOut(view, width: 120, height: 40)

        #expect(field.frame.maxX <= 120)
        #expect(field.frame.width > 0)
    }
}

@MainActor
@Suite("AppKit managed views")
struct AppKitManagedViewTests {
    @Test func labelsAreCreatedReusedAndUpdated() {
        nonisolated(unsafe) var text = "Before"
        let view = FlexView { Column { Label(text, lines: 1, id: "title") } }
        layOut(view, width: 200, height: 100)
        let field = view.subviews.compactMap { $0 as? NSTextField }.first
        #expect(field?.stringValue == "Before")

        text = "After"
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()

        #expect(view.subviews.compactMap { $0 as? NSTextField }.first === field)
        #expect(field?.stringValue == "After")
        #expect(view.subviews.count == 1)
    }

    @Test func removedDescriptionsRemoveTheirViews() {
        nonisolated(unsafe) var count = 3
        let view = FlexView { Column { for index in 0..<count { Label("Row \(index)") } } }
        layOut(view, width: 100, height: 100)
        #expect(view.subviews.count == 3)

        count = 1
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()

        #expect(view.subviews.count == 1)
    }

    @Test func boxesTakeTheirConfiguration() {
        let view = FlexView { Row { Box(color: .systemBlue, cornerRadius: 6).size(20) } }
        layOut(view, width: 100, height: 50)

        let box = view.subviews.first
        #expect(box?.frame.size == CGSize(width: 20, height: 20))
        #expect(box?.layer?.cornerRadius == 6)
    }

    @Test func sizeThatFitsWrapsToTheOfferedWidth() {
        let view = FlexView { Column { Label("The quick brown fox jumps over the lazy dog", lines: 0).shrink(1) } }

        let wide = view.sizeThatFits(CGSize(width: 1000, height: 1000))
        let narrow = view.sizeThatFits(CGSize(width: 100, height: 1000))

        #expect(narrow.width <= 100)
        #expect(narrow.height > wide.height * 1.5)
        #expect(view.intrinsicContentSize.width == wide.width)
    }

    @Test func measuringDoesNotMountViews() {
        let a = fixed()
        let view = FlexView { a.size(10, 10) }

        _ = view.sizeThatFits(CGSize(width: 100, height: 100))

        #expect(a.superview == nil)
    }
}
#endif
