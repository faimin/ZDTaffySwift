#if canImport(UIKit)
import CoreText
import Testing
import UIKit
import ZDLayoutCore
@testable import ZDLayout

@MainActor
private func layOut(_ view: UIView, width: CGFloat, height: CGFloat) {
    view.frame = CGRect(x: 0, y: 0, width: width, height: height)
    view.setNeedsLayout()
    view.layoutIfNeeded()
}

private func plainView() -> UIView {
    let view = UIView()
    view.backgroundColor = .red
    return view
}

/// A layer that reports a size, the way a custom drawing layer would.
@MainActor
private final class SizedLayer: CALayer, LayerMeasurable {
    var size = CGSize(width: 24, height: 12)
    func layoutSize(for constraint: MeasureConstraint) -> CGSize { size }
}

@MainActor
@Suite("Layer leaves")
struct LayerLeafTests {
    @Test func layersAreMountedAndPositionedLikeViews() {
        let a = CALayer(), b = CALayer()
        let view = FlexView {
            Row(gap: 10) { a.size(40, 20); b.size(30, 20) }
        }
        layOut(view, width: 200, height: 100)

        #expect(a.superlayer === view.layer)
        #expect(a.frame == CGRect(x: 0, y: 0, width: 40, height: 20))
        #expect(b.frame == CGRect(x: 50, y: 0, width: 30, height: 20))
        // A layer is not a view: nothing was added to `subviews`.
        #expect(view.subviews.isEmpty)
    }

    @Test func layersGrowAndShrinkLikeViews() {
        let a = CALayer(), b = CALayer()
        let view = FlexView { Row { a.size(40, 20); b.height(20).grow(1) } }
        layOut(view, width: 200, height: 50)

        #expect(b.frame == CGRect(x: 40, y: 0, width: 160, height: 20))
    }

    @Test func aLayerWithoutASizeHasNone() {
        let layer = CALayer()
        let view = FlexView { Row(alignItems: .start) { layer } }
        layOut(view, width: 200, height: 50)

        #expect(layer.frame.size == .zero)
    }

    @Test func aMeasurableLayerSizesItself() {
        let layer = SizedLayer()
        let view = FlexView { Row(alignItems: .start) { layer } }
        layOut(view, width: 200, height: 50)

        #expect(layer.frame.size == CGSize(width: 24, height: 12))
    }

    @Test func plainLayersDoNotUsePreferredFrameSize() {
        // `preferredFrameSize()` just echoes `bounds`; a layer must not size itself from its own last layout.
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 77, height: 33)
        let view = FlexView { Row(alignItems: .start) { layer } }
        layOut(view, width: 200, height: 50)

        #expect(layer.frame.size == .zero)
    }

    @Test func hiddenLayersTakeNoSpaceUntilShown() {
        let a = CALayer(), b = CALayer(), c = CALayer()
        let view = FlexView { Row(gap: 10) { a.size(30, 10); b.size(30, 10); c.size(30, 10) } }
        b.isHidden = true
        layOut(view, width: 200, height: 20)
        #expect(c.frame.minX == 40)

        b.isHidden = false
        view.setNeedsLayout()
        view.layoutIfNeeded()
        #expect(c.frame.minX == 80)
    }

    @Test func layersTheDescriptionDropsAreRemoved() {
        let a = CALayer(), b = CALayer()
        nonisolated(unsafe) var showsB = true
        let view = FlexView { Row { a.size(10, 10); if showsB { b.size(10, 10) } } }
        layOut(view, width: 100, height: 50)
        #expect(b.superlayer === view.layer)

        showsB = false
        view.setNeedsLayout()
        view.layoutIfNeeded()

        #expect(b.superlayer == nil)
        #expect(a.superlayer === view.layer)
    }

    @Test func layersLayOutWithoutImplicitAnimations() {
        let layer = CALayer()
        nonisolated(unsafe) var width: CGFloat = 40
        let view = FlexView { Row { layer.size(width, 20) } }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        window.addSubview(view)
        window.isHidden = false
        layOut(view, width: 200, height: 100)

        width = 120
        view.setNeedsLayout()
        view.layoutIfNeeded()

        #expect(layer.frame.width == 120)
        #expect(layer.animationKeys() == nil)
    }

    @Test func aTransformedLayerKeepsItsLayoutBox() {
        let layer = CALayer()
        layer.transform = CATransform3DMakeRotation(.pi / 4, 0, 0, 1)
        let view = FlexView { Row(alignItems: .start) { layer.size(40, 20) } }
        layOut(view, width: 200, height: 100)

        // The layout box is 40x20 at the origin, whatever the transform makes of `frame`.
        #expect(layer.bounds.size == CGSize(width: 40, height: 20))
        #expect(layer.position == CGPoint(x: 20, y: 10))
    }

    @Test func anchorPointsDoNotMoveTheLayoutBox() {
        let layer = CALayer()
        layer.anchorPoint = CGPoint(x: 0, y: 0)
        let view = FlexView { Row(alignItems: .start) { Leaf().width(30); layer.size(40, 20) } }
        layOut(view, width: 200, height: 100)

        #expect(layer.frame == CGRect(x: 30, y: 0, width: 40, height: 20))
    }
}

@MainActor
@Suite("Layers and views together")
struct LayerStackingTests {
    private func sublayers(of view: UIView, among wanted: [CALayer]) -> [CALayer] {
        (view.layer.sublayers ?? []).filter { layer in wanted.contains { $0 === layer } }
    }

    @Test func layersAndViewsStackInDescriptionOrder() {
        let l1 = CALayer(), l2 = CALayer()
        let v1 = plainView(), v2 = plainView()
        let view = FlexView {
            Row { l1.size(10, 10); v1.size(10, 10); l2.size(10, 10); v2.size(10, 10) }
        }
        layOut(view, width: 100, height: 20)

        #expect(sublayers(of: view, among: [l1, v1.layer, l2, v2.layer]) == [l1, v1.layer, l2, v2.layer])
    }

    @Test func reorderingTheDescriptionRestacks() {
        let l1 = CALayer(), l2 = CALayer()
        let v1 = plainView()
        nonisolated(unsafe) var flipped = false
        let view = FlexView {
            Row {
                if flipped { v1.size(10, 10); l2.size(10, 10); l1.size(10, 10) }
                else { l1.size(10, 10); v1.size(10, 10); l2.size(10, 10) }
            }
        }
        layOut(view, width: 100, height: 20)
        #expect(sublayers(of: view, among: [l1, v1.layer, l2]) == [l1, v1.layer, l2])

        flipped = true
        view.setNeedsLayout()
        view.layoutIfNeeded()

        #expect(sublayers(of: view, among: [l1, v1.layer, l2]) == [v1.layer, l2, l1])
    }

    @Test func aLayerFirstInTheDescriptionSitsBelowTheViews() {
        let l1 = CALayer()
        let v1 = plainView()
        let view = FlexView { Row { l1.size(10, 10); v1.size(10, 10) } }
        layOut(view, width: 100, height: 20)

        #expect(sublayers(of: view, among: [l1, v1.layer]) == [l1, v1.layer])
    }

    @Test func addingAViewLaterKeepsTheOrder() {
        let l1 = CALayer(), l2 = CALayer()
        let v1 = plainView(), v2 = plainView()
        nonisolated(unsafe) var showsV2 = false
        let view = FlexView {
            Row { l1.size(10, 10); v1.size(10, 10); l2.size(10, 10); if showsV2 { v2.size(10, 10) } }
        }
        layOut(view, width: 100, height: 20)

        showsV2 = true
        view.setNeedsLayout()
        view.layoutIfNeeded()

        #expect(sublayers(of: view, among: [l1, v1.layer, l2, v2.layer]) == [l1, v1.layer, l2, v2.layer])
    }

    @Test func viewsAndLayersMixInOneRow() {
        let layer = CALayer()
        let view = plainView()
        let host = FlexView { Row(gap: 8) { layer.size(20, 20); view.size(30, 20); Spacer(); Box(color: .blue).size(10, 20) } }
        layOut(host, width: 200, height: 40)

        #expect(layer.frame.minX == 0)
        #expect(view.frame == CGRect(x: 28, y: 0, width: 30, height: 20))
        #expect(host.subviews.last?.frame.maxX == 200)
    }
}

@MainActor
@Suite("Managed layers")
struct ManagedLayerTests {
    @Test func layersAreCreatedUpdatedAndReused() {
        nonisolated(unsafe) var color = UIColor.red.cgColor
        let view = FlexView {
            Row {
                ManagedLayer<CAGradientLayer>(id: "banner", make: { CAGradientLayer() }) {
                    $0.colors = [color, UIColor.blue.cgColor]
                }
                .size(50, 4)
            }
        }
        layOut(view, width: 100, height: 20)
        let gradient = view.layer.sublayers?.compactMap { $0 as? CAGradientLayer }.first
        #expect(gradient?.frame == CGRect(x: 0, y: 0, width: 50, height: 4))

        color = UIColor.green.cgColor
        view.setNeedsLayout()
        view.layoutIfNeeded()

        #expect(view.layer.sublayers?.compactMap { $0 as? CAGradientLayer }.first === gradient)
        #expect((gradient?.colors?.first as! CGColor) == UIColor.green.cgColor)
    }

    @Test func descriptionsThatDisappearRemoveTheirLayers() {
        nonisolated(unsafe) var count = 3
        let view = FlexView {
            Column { for index in 0..<count { ManagedLayer<CALayer>(make: { CALayer() }).size(10, 10).margin(Edges(top: CGFloat(index))) } }
        }
        layOut(view, width: 100, height: 100)
        #expect(view.layer.sublayers?.count == 3)

        count = 1
        view.setNeedsLayout()
        view.layoutIfNeeded()

        #expect(view.layer.sublayers?.count == 1)
    }

    @Test func explicitIdsKeepTheSameLayerWhenSiblingsChange() {
        nonisolated(unsafe) var showsFirst = true
        let view = FlexView {
            Column {
                if showsFirst { ManagedLayer<CALayer>(make: { CALayer() }).size(10, 10) }
                ManagedLayer<CALayer>(id: "kept", make: { CALayer() }).size(10, 10)
            }
        }
        layOut(view, width: 100, height: 100)
        let all = view.layer.sublayers ?? []
        let kept = all.last

        showsFirst = false
        view.setNeedsLayout()
        view.layoutIfNeeded()

        #expect(view.layer.sublayers?.count == 1)
        #expect(view.layer.sublayers?.first === kept)
    }

    @Test func measuringDoesNotAttachLayers() {
        let view = FlexView { ManagedLayer<CALayer>(id: "x", make: { CALayer() }).size(10, 10) }

        _ = view.sizeThatFits(CGSize(width: 100, height: 100))

        #expect(view.layer.sublayers?.isEmpty ?? true)
    }
}

@MainActor
@Suite("TextLayer")
struct TextLayerTests {
    private let sentence = "The quick brown fox jumps over the lazy dog"

    private func textLayer(in view: UIView) -> CATextLayer? {
        view.layer.sublayers?.compactMap { $0 as? CATextLayer }.first
    }

    @Test func wrapsToTheWidthItIsGiven() {
        let view = FlexView { Column(alignItems: .start) { TextLayer(sentence, font: .systemFont(ofSize: 15)).width(120) } }
        layOut(view, width: 300, height: 300)

        let layer = textLayer(in: view)
        #expect(layer?.frame.width == 120)
        #expect((layer?.frame.height ?? 0) > UIFont.systemFont(ofSize: 15).lineHeight * 1.5)
        #expect(layer?.isWrapped == true)
        #expect(layer?.string as? String == sentence)
    }

    @Test func aSingleLineTruncatesAndMayShrinkToNothing() {
        let view = FlexView {
            Row(gap: 8) { plainView().size(40, 20); TextLayer(sentence, wraps: false).grow(1).shrink(1) }
        }
        layOut(view, width: 120, height: 40)

        let layer = textLayer(in: view)
        #expect(layer?.isWrapped == false)
        #expect(layer?.truncationMode == .end)
        #expect((layer?.frame.maxX ?? 999) <= 120)
        #expect((layer?.frame.width ?? 0) > 0)
    }

    @Test func wrappingTextBesideAFixedViewStaysInsideTheRow() {
        let view = FlexView {
            Row(gap: 8, alignItems: .start) { plainView().size(40); TextLayer(sentence, font: .systemFont(ofSize: 15)).shrink(1) }
        }
        layOut(view, width: 160, height: 300)

        let layer = textLayer(in: view)
        #expect((layer?.frame.maxX ?? 999) <= 160)
        #expect((layer?.frame.height ?? 0) > UIFont.systemFont(ofSize: 15).lineHeight * 1.5)
    }

    @Test func contentsScaleFollowsTheScreen() {
        let view = FlexView { Column { TextLayer("Sharp") } }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        window.addSubview(view)
        window.isHidden = false
        layOut(view, width: 200, height: 100)

        #expect(textLayer(in: view)?.contentsScale == window.screen.scale)
    }

    @Test func textAndFontUpdateInPlace() {
        nonisolated(unsafe) var text = "Before"
        let view = FlexView { Column(alignItems: .start) { TextLayer(text, font: .systemFont(ofSize: 15), id: "t") } }
        layOut(view, width: 300, height: 100)
        let layer = textLayer(in: view)
        let before = layer?.frame.width ?? 0

        text = "After a rather longer text"
        view.setNeedsLayout()
        view.layoutIfNeeded()

        #expect(textLayer(in: view) === layer)
        #expect(layer?.string as? String == "After a rather longer text")
        #expect((layer?.frame.width ?? 0) > before)
    }

    @Test func drawsWithTheFontItMeasuresWith() {
        // System fonts have internal names ("`.SFUI-Regular`") that CoreText cannot look up, so building the
        // layer's font from `fontName` silently fell back to a serif face while the layout measured the real one.
        for font in [UIFont.systemFont(ofSize: 15), .preferredFont(forTextStyle: .subheadline), .boldSystemFont(ofSize: 20), UIFont(name: "Menlo-Regular", size: 13)!] {
            let view = FlexView { Column { TextLayer("Sample", font: font) } }
            layOut(view, width: 200, height: 100)

            let layer = textLayer(in: view)
            let drawn = layer?.font as! CTFont
            #expect(CTFontCopyPostScriptName(drawn) as String == font.fontName, "\(font.fontName)")
            #expect(CTFontGetSize(drawn) == font.pointSize)
            #expect(layer?.fontSize == font.pointSize)
        }
    }

    @Test func smallestWidthIsTheLongestWord() {
        let font = UIFont.systemFont(ofSize: 15)
        let view = FlexView { TextLayer("an unbreakable word in a sentence", font: font) }
        let constraint = MeasureConstraint(availableWidth: .minContent, availableHeight: .maxContent)

        let width = view.layoutSize(for: constraint).width

        #expect(width == ceil(("unbreakable" as NSString).size(withAttributes: [.font: font]).width))
    }
}
#endif
