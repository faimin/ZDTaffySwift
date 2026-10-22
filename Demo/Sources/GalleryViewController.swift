import UIKit
import ZDLayout
import ZDLayoutCore

/// A CSS grid: fractional columns, square cells through an aspect ratio, and items that span columns.
final class GalleryViewController: UIViewController {
    private let palette: [UIColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemBlue, .systemIndigo, .systemPurple, .systemPink]

    private lazy var scroll = FlexScrollView(insets: .layoutMargins) { [palette] in
        Column(gap: 12) {
            Label("Photos", font: .preferredFont(forTextStyle: .largeTitle), lines: 1)
            Grid(columns: [.fr(1), .fr(1), .fr(1)], autoRows: [.auto], gap: 4) {
                for index in 0..<27 {
                    let wide = index % 9 == 0
                    Box(color: palette[index % palette.count], cornerRadius: 6)
                        .aspectRatio(wide ? 2 + 4.0 / 340 : 1)
                        .gridColumn(.span(wide ? 2 : 1))
                }
            }
            Label("The first cell of every row of nine spans two columns; the rest are square.", font: .preferredFont(forTextStyle: .footnote), color: .secondaryLabel)
        }
        .padding(vertical: 8)
    }

    override func loadView() {
        view = scroll
        scroll.backgroundColor = .systemBackground
    }
}
