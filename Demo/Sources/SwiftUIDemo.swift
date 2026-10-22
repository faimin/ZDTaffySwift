import SwiftUI
import UIKit
import ZDLayoutCore
import ZDLayoutSwiftUI

/// `FlexStack` is a SwiftUI `Layout`, so it needs iOS 16; the rest of the demo still runs on iOS 15.
@available(iOS 16.0, *)
struct FlexDemoView: View {
    @State private var showsBadge = true
    @State private var showsExtraTags = false

    private let tags = ["Flexbox", "Grid", "Block", "UIKit", "SwiftUI", "AppKit", "Taffy", "Rust"]
    private let colors: [Color] = [.red, .orange, .yellow, .green, .teal, .blue, .indigo, .purple, .pink]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                section("A row: the middle grows and shrinks") {
                    FlexStack(.row, gap: 12, alignItems: .center) {
                        Circle().fill(.indigo).frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Zero.D.Saber").font(.headline)
                            Text("@zero_d_saber").foregroundStyle(.secondary)
                        }
                        .flexItem(grow: 1, shrink: 1)
                        if showsBadge {
                            Text("PRO")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.orange))
                        }
                    }
                }

                section("Wrapping: tags move to the next line") {
                    FlexStack(.row, gap: 8, wraps: true) {
                        ForEach(showsExtraTags ? tags + ["Swift 6", "BoltFFI", "iOS 15+", "macOS"] : tags, id: \.self) { tag in
                            Text(tag)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        }
                    }
                }

                section("Grid: 1fr 1fr 2fr, one item spans two columns") {
                    FlexStack(columns: [.fr(1), .fr(1), .fr(2)], gap: 8) {
                        ForEach(0..<7, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colors[index % colors.count])
                                .frame(height: 48)
                                .overlay(Text("\(index + 1)").foregroundStyle(.white).bold())
                                .gridItem(column: index == 0 ? .span(2) : .auto)
                        }
                    }
                }

                section("Space between") {
                    FlexStack(.row, justifyContent: .spaceBetween) {
                        ForEach(0..<3, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 8).fill(colors[index * 3]).frame(width: 64, height: 40)
                        }
                    }
                }

                section("Wrapping text beside a fixed view") {
                    FlexStack(.row, gap: 12, alignItems: .start) {
                        RoundedRectangle(cornerRadius: 10).fill(.teal).frame(width: 56, height: 56)
                        Text("The text takes whatever width is left and wraps inside it, because it is allowed to shrink; the square never does.")
                            .flexItem(grow: 1, shrink: 1)
                    }
                }

                VStack(spacing: 8) {
                    Toggle("Show PRO badge", isOn: $showsBadge)
                    Toggle("More tags", isOn: $showsExtraTags)
                }
            }
            .padding(16)
        }
        .animation(.default, value: showsBadge)
        .animation(.default, value: showsExtraTags)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.footnote).foregroundStyle(.secondary)
            content()
        }
    }
}

/// The UIKit tab bar needs a view controller; on iOS 15, where `FlexStack` is unavailable, say so.
func makeSwiftUIDemoController() -> UIViewController {
    if #available(iOS 16.0, *) {
        // A real app gets this from the user's language. The `-rtl YES` launch argument forces it, and a hosting
        // controller created later does not inherit the semantic attribute set on the views that already exist.
        let direction: LayoutDirection = UserDefaults.standard.bool(forKey: "rtl") ? .rightToLeft : .leftToRight
        return UIHostingController(rootView: FlexDemoView().environment(\.layoutDirection, direction))
    }
    let controller = UIViewController()
    let label = UILabel()
    label.text = "FlexStack needs iOS 16."
    label.textAlignment = .center
    label.frame = controller.view.bounds
    label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    controller.view.addSubview(label)
    return controller
}
