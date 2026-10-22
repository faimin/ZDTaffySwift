import UIKit
import ZDLayout
import ZDLayoutCore

/// Settings-style rows, plus controls for right-to-left layout and hidden views.
final class FormViewController: UIViewController {
    private var rtl = false
    private var showsFooter = true

    private lazy var scroll: FlexScrollView = FlexScrollView(insets: .layoutMargins) { [unowned self] in
        Column(gap: 8) {
            section("Layout")
            row("Right-to-left", id: "rtl", isOn: rtl) { [unowned self] on in
                rtl = on
                Direction.apply(on ? .forceRightToLeft : .unspecified, to: tabBarController?.view ?? view)
            }
            row("Show footer", id: "footer", isOn: showsFooter) { [unowned self] on in
                showsFooter = on
                scroll.setNeedsLayout()
            }
            section("Text")
            Label("Change the text size in Settings → Display & Brightness → Text Size (or with simctl ui content_size). Every label here follows it, and the rows grow instead of clipping.")
                .shrink(1)
            section("Rows")
            for (index, title) in ["Notifications", "Background refresh", "A setting with a rather long title that has to wrap"].enumerated() {
                row(title, id: "row\(index)", isOn: index != 1) { _ in }
            }
            if showsFooter {
                Label("Footer — hidden with the switch above, and the space it took goes with it.", font: .preferredFont(forTextStyle: .footnote), color: .secondaryLabel)
                    .shrink(1)
                    .margin(Edges(top: 12))
            }
        }
        .padding(vertical: 8)
    }

    private func section(_ title: String) -> LayoutNode {
        Label(title.uppercased(), font: .preferredFont(forTextStyle: .footnote), color: .secondaryLabel, lines: 1)
            .margin(Edges(top: 16, bottom: 4))
    }

    private func row(_ title: String, id: String, isOn: Bool, onChange: @escaping @MainActor (Bool) -> Void) -> LayoutNode {
        Row(gap: 12, alignItems: .center) {
            Label(title).grow(1).shrink(1)
            Managed<UISwitch>(id: id, make: {
                let toggle = UISwitch()
                toggle.addAction(UIAction { action in
                    onChange((action.sender as? UISwitch)?.isOn ?? false)
                }, for: .valueChanged)
                return toggle
            }) { $0.isOn = isOn }
        }
        .padding(vertical: 6)
    }

    override func loadView() {
        view = scroll
        scroll.backgroundColor = .systemGroupedBackground
    }
}
