import UIKit
import ZDLayout
import ZDLayoutCore

/// Rows, columns, a Spacer, wrapping text, conditional content and views the framework creates and reuses.
final class ProfileViewController: UIViewController {
    private var showsBadge = true
    private var isFollowing = false

    /// The stats row has no view of its own; this guide lets an ordinary view be pinned around it with Auto Layout.
    private let statsGuide = FlexGuide()
    private let statsBackground: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 14
        view.layer.cornerCurve = .continuous
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var scroll: FlexScrollView = FlexScrollView(insets: .layoutMargins) { [unowned self] in
        Column(gap: 20) {
            header
            Label(
                "Building layout tools for UIKit. I like small APIs, exact pixels and text that wraps where it should, "
                + "even when the user picks the largest Dynamic Type size.",
                color: .label
            )
            Row(gap: 12) {
                stat("128", "Posts")
                stat("4.2K", "Followers")
                stat("312", "Following")
            }
            .guide(statsGuide)
            Row(gap: 12) {
                followButton.grow(1).basis(0).height(44)
                Managed<UIButton>(id: "message", make: { Self.button("Message", filled: false) }).grow(1).basis(0).height(44)
            }
            Box(color: .separator).height(1 / UIScreen.main.scale)
            Label("Toggle sections", font: .preferredFont(forTextStyle: .footnote), color: .secondaryLabel, lines: 1)
            Row(gap: 12, alignItems: .center) {
                Label("Show PRO badge").grow(1).shrink(1)
                Managed<UISwitch>(id: "badge-switch", make: { [unowned self] in
                    let toggle = UISwitch()
                    toggle.isOn = showsBadge
                    toggle.addAction(UIAction { [unowned self] action in
                        showsBadge = (action.sender as? UISwitch)?.isOn ?? true
                        scroll.setNeedsLayout()
                    }, for: .valueChanged)
                    return toggle
                })
            }
        }
        .padding(vertical: 16)
    }

    private var header: LayoutNode {
        Row(gap: 16, alignItems: .center) {
            Box(color: .systemIndigo, cornerRadius: 36, id: "avatar").size(72)
            Column(gap: 4) {
                Row(gap: 8, alignItems: .center) {
                    Label("Zero.D.Saber", font: .preferredFont(forTextStyle: .title2), lines: 1).shrink(1)
                    if showsBadge {
                        Managed<PillLabel>(id: "pro", make: {
                            let pill = PillLabel()
                            pill.text = "PRO"
                            pill.font = .preferredFont(forTextStyle: .caption1)
                            pill.textColor = .white
                            pill.backgroundColor = .systemOrange
                            return pill
                        })
                    }
                }
                Label("@zero_d_saber", color: .secondaryLabel, lines: 1).shrink(1)
            }
            .grow(1)
            .shrink(1)
        }
        .layoutNode
    }

    private var followButton: Managed<UIButton> {
        Managed<UIButton>(id: "follow", make: { [unowned self] in
            let button = Self.button("Follow", filled: true)
            button.addAction(UIAction { [unowned self] _ in
                isFollowing.toggle()
                scroll.setNeedsLayout()
            }, for: .touchUpInside)
            return button
        }) { [isFollowing] button in
            button.configuration?.title = isFollowing ? "Following" : "Follow"
        }
    }

    private func stat(_ value: String, _ title: String) -> LayoutNode {
        Column(gap: 2, alignItems: .center) {
            Label(value, font: .preferredFont(forTextStyle: .title3), lines: 1, alignment: .center)
            Label(title, font: .preferredFont(forTextStyle: .caption1), color: .secondaryLabel, lines: 1, alignment: .center)
        }
        .grow(1)
        .basis(0)
        .layoutNode
    }

    private static func button(_ title: String, filled: Bool) -> UIButton {
        var configuration: UIButton.Configuration = filled ? .filled() : .tinted()
        configuration.title = title
        return UIButton(configuration: configuration)
    }

    override func loadView() {
        view = scroll
        scroll.backgroundColor = .systemBackground
        // Sits behind the content and hugs the (virtual) stats row, 8pt larger on every side.
        scroll.insertSubview(statsBackground, at: 0)
        statsGuide.whenInstalled { [statsBackground] guide in
            NSLayoutConstraint.activate([
                statsBackground.leftAnchor.constraint(equalTo: guide.leftAnchor, constant: -8),
                statsBackground.topAnchor.constraint(equalTo: guide.topAnchor, constant: -8),
                statsBackground.widthAnchor.constraint(equalTo: guide.widthAnchor, constant: 16),
                statsBackground.heightAnchor.constraint(equalTo: guide.heightAnchor, constant: 16),
            ])
        }
    }
}
