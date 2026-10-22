#if canImport(UIKit)
import Testing
import UIKit
import ZDLayoutCore
@testable import ZDLayout

private func fixed(_ width: CGFloat, _ height: CGFloat) -> UIView {
    let view = UIView()
    view.backgroundColor = .red
    // A plain UIView has no intrinsic size; give it one through its style at the call site.
    return view
}

private func label(_ text: String, lines: Int = 1) -> UILabel {
    let label = UILabel()
    label.text = text
    label.numberOfLines = lines
    label.font = .systemFont(ofSize: 14)
    return label
}

@MainActor
private func layout(_ view: UIView, width: CGFloat, height: CGFloat) {
    view.frame = CGRect(x: 0, y: 0, width: width, height: height)
    view.setNeedsLayout()
    view.layoutIfNeeded()
}

@MainActor
@Suite("FlexView")
struct FlexViewTests {
    @Test func positionsSubviewsAndMountsThem() {
        let a = fixed(0, 0), b = fixed(0, 0)
        let view = FlexView {
            Row(gap: 10) {
                a.size(40, 20)
                b.size(30, 20)
            }
        }
        layout(view, width: 200, height: 100)

        #expect(a.superview === view)
        #expect(b.superview === view)
        #expect(a.frame == CGRect(x: 0, y: 0, width: 40, height: 20))
        #expect(b.frame == CGRect(x: 50, y: 0, width: 30, height: 20))
    }

    @Test func descriptionIsReEvaluatedEveryPass() {
        let a = fixed(0, 0), b = fixed(0, 0)
        nonisolated(unsafe) var showsB = true
        let view = FlexView {
            Row {
                a.size(40, 20)
                if showsB { b.size(30, 20) }
            }
        }
        layout(view, width: 200, height: 100)
        #expect(b.superview === view)

        showsB = false
        view.setNeedsLayout()
        view.layoutIfNeeded()
        #expect(b.superview == nil)
        #expect(a.superview === view)

        showsB = true
        view.setNeedsLayout()
        view.layoutIfNeeded()
        #expect(b.superview === view)
    }

    @Test func subviewOrderFollowsDescriptionOrder() {
        let a = fixed(0, 0), b = fixed(0, 0), c = fixed(0, 0)
        nonisolated(unsafe) var order: [UIView] = [a, b, c]
        let view = FlexView {
            Row { for v in order { v.size(10, 10) } }
        }
        layout(view, width: 100, height: 20)
        #expect(view.subviews == [a, b, c])

        order = [c, a, b]
        view.setNeedsLayout()
        view.layoutIfNeeded()
        #expect(view.subviews == [c, a, b])
    }

    @Test func hiddenViewsTakeNoSpaceUntilShown() {
        let a = fixed(0, 0), b = fixed(0, 0), c = fixed(0, 0)
        let view = FlexView {
            Row(gap: 10) {
                a.size(30, 10)
                b.size(30, 10)
                c.size(30, 10)
            }
        }
        b.isHidden = true
        layout(view, width: 200, height: 20)
        #expect(c.frame.minX == 40)

        b.isHidden = false
        view.setNeedsLayout()
        view.layoutIfNeeded()
        #expect(c.frame.minX == 80)
    }

    @Test func rightToLeftMirrorsRows() {
        let a = fixed(0, 0), b = fixed(0, 0)
        let view = FlexView {
            Row {
                a.size(30, 10)
                b.size(30, 10)
            }
            .padding(Edges(leading: 20))
        }
        view.semanticContentAttribute = .forceRightToLeft
        layout(view, width: 200, height: 20)

        #expect(a.frame.maxX == 180)
        #expect(b.frame.maxX == 150)
    }

    @Test func layoutMarginsInsetTheContent() {
        let a = fixed(0, 0)
        let view = FlexView(insets: .layoutMargins) { a.size(10, 10) }
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 4, leading: 6, bottom: 8, trailing: 10)
        layout(view, width: 100, height: 50)

        #expect(a.frame.origin == CGPoint(x: 6, y: 4))
    }

    @Test func subclassesDescribeContentInBody() {
        final class Header: FlexView {
            let icon = UIView(), title = UILabel()
            @LayoutBuilder override func body() -> [LayoutNode] {
                Row(gap: 8, alignItems: .center) {
                    icon.size(20)
                    title.grow(1)
                }
                .grow(1)
            }
        }
        let header = Header(frame: .zero)
        header.title.text = "Hi"
        layout(header, width: 200, height: 40)

        #expect(header.icon.frame == CGRect(x: 0, y: 10, width: 20, height: 20))
        #expect(header.title.frame.minX == 28)
        #expect(header.title.frame.maxX == 200)
    }

    @Test func gridContainersLayOutUIViews() {
        let a = fixed(0, 0), b = fixed(0, 0)
        let view = FlexView {
            Grid(columns: [.fr(1), .fr(3)], rows: [.fixed(30)], gap: 0) {
                a
                b
            }
        }
        layout(view, width: 200, height: 100)

        #expect(a.frame == CGRect(x: 0, y: 0, width: 50, height: 30))
        #expect(b.frame == CGRect(x: 50, y: 0, width: 150, height: 30))
    }

    @Test func framesLandOnDevicePixels() {
        let views = (0..<3).map { _ in fixed(0, 0) }
        let view = FlexView {
            Row { for v in views { v.grow(1).height(10) } }
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.addSubview(view)
        layout(view, width: 100, height: 10)

        // Edges are multiples of 1/scale up to floating point error (33.333…×3 is 99.99999999999999).
        let scale = window.screen.scale
        func isOnPixel(_ value: CGFloat) -> Bool { abs(value * scale - (value * scale).rounded()) < 1e-6 }
        for child in views {
            #expect(isOnPixel(child.frame.minX))
            #expect(isOnPixel(child.frame.maxX))
        }
        #expect(abs(views[2].frame.maxX - 100) < 1e-6)
    }

    #if DEBUG
    @Test func debugOverlayIsAddedAndRemoved() {
        let view = FlexView { fixed(0, 0).size(10, 10) }
        layout(view, width: 50, height: 50)
        #expect(view.layer.sublayers?.contains { $0 is CAShapeLayer } != true)

        view.showsLayoutDebugOverlay = true
        view.layoutIfNeeded()
        #expect(view.layer.sublayers?.contains { $0 is CAShapeLayer } == true)

        view.showsLayoutDebugOverlay = false
        view.layoutIfNeeded()
        #expect(view.layer.sublayers?.contains { $0 is CAShapeLayer } != true)
    }
    #endif

    @Test func debugDescriptionListsTheTree() {
        let a = fixed(0, 0)
        let view = FlexView { Row { a.size(10, 10) } }
        layout(view, width: 50, height: 50)

        #expect(view.debugDescription.contains("UIView (0.0, 0.0, 10.0, 10.0)"))
        #expect(view.debugDescription.contains("Flex row"))
    }
}

@MainActor
@Suite("Measuring")
struct MeasuringTests {
    @Test func labelsWrapToTheOfferedWidth() {
        let text = label("The quick brown fox jumps over the lazy dog", lines: 0)
        let view = FlexView { text }

        let wide = view.sizeThatFits(CGSize(width: 1000, height: CGFloat.greatestFiniteMagnitude))
        let narrow = view.sizeThatFits(CGSize(width: 100, height: CGFloat.greatestFiniteMagnitude))

        #expect(narrow.width <= 100)
        #expect(narrow.height > wide.height * 1.5)
        #expect(wide.height == text.sizeThatFits(CGSize(width: 1000, height: CGFloat.greatestFiniteMagnitude)).height)
    }

    @Test func labelHeightFollowsAssignedWidthInsideARow() {
        let icon = UIView()
        let text = label("The quick brown fox jumps over the lazy dog", lines: 0)
        let view = FlexView {
            Row(gap: 8) {
                icon.size(40)
                text.shrink(1)
            }
        }
        layout(view, width: 160, height: 300)

        #expect(text.frame.width <= 160 - 48)
        #expect(text.frame.height > label("x").intrinsicContentSize.height)
        #expect(text.frame.maxX <= 160)
    }

    @Test func unconstrainedAndZeroProposalsMeanNoLimit() {
        let text = label("A fairly long single line of text")
        let view = FlexView { text }

        let natural = text.intrinsicContentSize.width
        #expect(view.sizeThatFits(.zero).width == natural)
        #expect(view.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: 10)).width == natural)
        #expect(view.intrinsicContentSize.width == natural)
    }

    @Test func systemLayoutSizeFittingPinsOnlyRequiredAxes() {
        let text = label("The quick brown fox jumps over the lazy dog", lines: 0)
        let view = FlexView { text }

        let pinned = view.systemLayoutSizeFitting(
            CGSize(width: 120, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let free = view.systemLayoutSizeFitting(
            CGSize(width: 120, height: 0),
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .fittingSizeLevel
        )

        #expect(pinned.width <= 120)
        #expect(pinned.height > free.height)
    }

    @Test func nestedFlexViewIsMeasuredAsALeaf() {
        let inner = FlexView {
            Column { label("one"); label("two") }
        }
        let outer = FlexView {
            Row(alignItems: .start) { inner }
        }

        let expected = inner.sizeThatFits(CGSize(width: 1000, height: 1000))
        #expect(outer.sizeThatFits(.zero) == expected)

        layout(outer, width: 300, height: 100)
        #expect(inner.frame.size == expected)
    }

    @Test func measureDoesNotMountOrMoveViews() {
        let a = fixed(0, 0)
        let view = FlexView { a.size(10, 10) }

        _ = view.sizeThatFits(CGSize(width: 100, height: 100))

        #expect(a.superview == nil)
    }
}

@MainActor
@Suite("FlexScrollView")
struct FlexScrollViewTests {
    @Test func verticalContentSizeFollowsContent() {
        let views = (0..<5).map { _ in fixed(0, 0) }
        let scroll = FlexScrollView {
            Column(gap: 10) { for v in views { v.height(40) } }
        }
        layout(scroll, width: 320, height: 200)

        #expect(scroll.contentSize == CGSize(width: 320, height: 5 * 40 + 4 * 10))
        #expect(views[0].frame == CGRect(x: 0, y: 0, width: 320, height: 40))
        #expect(views[4].frame.minY == CGFloat(4 * 50), "minY bits: \(views[4].frame.minY.bitPattern) vs \((200 as CGFloat).bitPattern)")
    }

    @Test func contentSizeTracksStateChanges() {
        let views = (0..<3).map { _ in fixed(0, 0) }
        nonisolated(unsafe) var count = 1
        let scroll = FlexScrollView {
            Column { for v in views.prefix(count) { v.height(100) } }
        }
        layout(scroll, width: 100, height: 100)
        #expect(scroll.contentSize.height == 100)

        count = 3
        scroll.setNeedsLayout()
        scroll.layoutIfNeeded()
        #expect(scroll.contentSize.height == 300)
    }

    @Test func scrollingDoesNotMoveContentInItsOwnCoordinates() {
        let views = (0..<5).map { _ in fixed(0, 0) }
        let scroll = FlexScrollView {
            Column { for v in views { v.height(100) } }
        }
        layout(scroll, width: 200, height: 200)

        scroll.contentOffset = CGPoint(x: 0, y: 150)
        scroll.setNeedsLayout()
        scroll.layoutIfNeeded()

        // Subview frames live in content coordinates, which do not shift with the offset.
        #expect(views[0].frame == CGRect(x: 0, y: 0, width: 200, height: 100))
        #expect(views[3].frame.minY == 300)
        #expect(scroll.contentSize.height == 500)
    }

    @Test func horizontalAxisScrollsSideways() {
        let views = (0..<4).map { _ in fixed(0, 0) }
        let scroll = FlexScrollView(axis: .horizontal) {
            Row { for v in views { v.width(80).shrink(0) } }
        }
        layout(scroll, width: 200, height: 60)

        #expect(scroll.contentSize == CGSize(width: 320, height: 60))
        #expect(views[3].frame.minX == 240)
    }

    @Test func wrappingTextMakesTheContentTaller() {
        let text = label(String(repeating: "word ", count: 80), lines: 0)
        let scroll = FlexScrollView { text }
        layout(scroll, width: 200, height: 100)

        #expect(scroll.contentSize.width == 200)
        #expect(scroll.contentSize.height > 100)
    }
}

@MainActor
@Suite("Cells")
struct CellTests {
    @Test func collectionViewListCellsSelfSizeFromTheDSL() async throws {
        let long = "The quick brown fox jumps over the lazy dog. " + String(repeating: "More words. ", count: 12)
        let texts = ["Short", long]

        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        config.showsSeparators = false
        let layout = UICollectionViewCompositionalLayout.list(using: config)
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 600), collectionViewLayout: layout)

        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, String> { cell, _, text in
            let title = label(text, lines: 0)
            cell.contentConfiguration = FlexContentConfiguration(insets: .none) {
                Row(alignItems: .start) { title.grow(1).shrink(1) }.padding(12)
            }
        }
        let dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: collection) { view, indexPath, text in
            view.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: text)
        }
        let window = UIWindow(frame: collection.frame)
        window.addSubview(collection)
        window.isHidden = false

        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(texts)
        await dataSource.apply(snapshot, animatingDifferences: false)
        // Self-sizing settles over a few layout passes.
        for _ in 0..<5 {
            collection.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 30_000_000)
        }

        let short = try #require(collection.cellForItem(at: IndexPath(item: 0, section: 0)))
        let tall = try #require(collection.cellForItem(at: IndexPath(item: 1, section: 0)))
        let padding: CGFloat = 24
        let singleLine = label("Short").sizeThatFits(CGSize(width: 296, height: CGFloat.greatestFiniteMagnitude)).height
        let wrapped = label(long, lines: 0).sizeThatFits(CGSize(width: 296, height: CGFloat.greatestFiniteMagnitude)).height

        #expect(wrapped > singleLine * 3)
        #expect(abs(short.frame.height - (singleLine + padding)) < 1)
        #expect(abs(tall.frame.height - (wrapped + padding)) < 1)
        #expect(tall.frame.width == 320)
    }
}

@MainActor
@Suite("Table cells")
struct TableCellTests {
    @Test func tableViewCellsSelfSizeFromTheDSL() async throws {
        let long = "The quick brown fox jumps over the lazy dog. " + String(repeating: "More words. ", count: 12)
        let table = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 600), style: .plain)
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 44
        table.separatorStyle = .none
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        let source = UITableViewDiffableDataSource<Int, String>(tableView: table) { table, indexPath, text in
            let cell = table.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            let title = label(text, lines: 0)
            cell.contentConfiguration = FlexContentConfiguration {
                Row(alignItems: .start) { title.grow(1).shrink(1) }.padding(12)
            }
            return cell
        }
        let window = UIWindow(frame: table.frame)
        window.addSubview(table)
        window.isHidden = false

        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(["Short", long])
        await source.apply(snapshot, animatingDifferences: false)
        for _ in 0..<5 {
            table.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 30_000_000)
        }

        let singleLine = label("Short").sizeThatFits(CGSize(width: 296, height: CGFloat.greatestFiniteMagnitude)).height
        let wrapped = label(long, lines: 0).sizeThatFits(CGSize(width: 296, height: CGFloat.greatestFiniteMagnitude)).height

        #expect(abs(table.rectForRow(at: IndexPath(row: 0, section: 0)).height - (singleLine + 24)) < 1)
        #expect(abs(table.rectForRow(at: IndexPath(row: 1, section: 0)).height - (wrapped + 24)) < 1)
    }
}
#endif
