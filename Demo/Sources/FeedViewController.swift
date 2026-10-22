import UIKit
import ZDLayout
import ZDLayoutCore

/// Self-sizing collection view cells described with the DSL.
final class FeedViewController: UIViewController {
    private struct Post: Hashable {
        let id: Int
        let name: String
        let time: String
        let body: String
        let color: UIColor
    }

    private let posts: [Post] = {
        let bodies = [
            "Short and sweet.",
            "Layout is just arithmetic. The hard part is deciding what to do when the numbers do not fit.",
            "Flexbox, Grid and Block share one engine, so a screen can mix them: a grid of cards inside a column inside a scroll view, without nesting views.",
            "English, 中文, العربية — text measures and wraps in whatever the user reads, and the row mirrors for right-to-left languages.",
            "Self-sizing cells ask for a height at a given width. Here that question is answered by the same solver that positions the subviews, so the two can never disagree about how tall the text is.",
        ]
        let names = ["Ada", "Linus", "Grace", "Dennis", "Barbara", "Ken"]
        let colors: [UIColor] = [.systemRed, .systemBlue, .systemGreen, .systemOrange, .systemPurple, .systemTeal]
        return (0..<30).map { index in
            Post(id: index, name: names[index % names.count], time: "\(index + 1)m", body: bodies[index % bodies.count], color: colors[index % colors.count])
        }
    }()

    private var collection: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, Post>!

    override func viewDidLoad() {
        super.viewDidLoad()
        collection = UICollectionView(frame: view.bounds, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: UICollectionLayoutListConfiguration(appearance: .plain)))
        collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(collection)

        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, Post> { cell, _, post in
            cell.contentConfiguration = FlexContentConfiguration {
                Row(gap: 12, alignItems: .start) {
                    Box(color: post.color, cornerRadius: 20).size(40)
                    Column(gap: 4) {
                        Row(gap: 8, alignItems: .baseline) {
                            Label(post.name, font: .preferredFont(forTextStyle: .headline), lines: 1).shrink(1)
                            Spacer()
                            Label(post.time, font: .preferredFont(forTextStyle: .caption1), color: .secondaryLabel, lines: 1)
                        }
                        Label(post.body, font: .preferredFont(forTextStyle: .subheadline)).shrink(1)
                    }
                    .grow(1)
                    .shrink(1)
                }
                .padding(12)
            }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collection) { view, indexPath, post in
            view.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: post)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Post>()
        snapshot.appendSections([0])
        snapshot.appendItems(posts)
        dataSource.apply(snapshot, animatingDifferences: false)
    }
}
