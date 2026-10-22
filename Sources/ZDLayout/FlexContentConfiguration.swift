#if canImport(UIKit)
import UIKit
import ZDLayoutCore

/// A `UIContentConfiguration` that describes a cell's content with the layout DSL.
///
/// ```swift
/// cell.contentConfiguration = FlexContentConfiguration(insets: .layoutMargins) {
///     Row(gap: 8, alignItems: .center) { icon.size(24); title.grow(1) }
/// }
/// ```
public struct FlexContentConfiguration: UIContentConfiguration {
    let insets: FlexInsets
    let content: @MainActor () -> [LayoutNode]

    public init(insets: FlexInsets = .none, @LayoutBuilder content: @escaping @MainActor () -> [LayoutNode]) {
        self.insets = insets
        self.content = content
    }

    public func makeContentView() -> UIView & UIContentView {
        FlexContentView(configuration: self)
    }

    public func updated(for state: UIConfigurationState) -> FlexContentConfiguration {
        self
    }
}

@MainActor
final class FlexContentView: FlexView, UIContentView {
    var configuration: UIContentConfiguration {
        didSet { apply() }
    }

    init(configuration: FlexContentConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
        apply()
    }

    required init?(coder: NSCoder) {
        fatalError("FlexContentView is created by FlexContentConfiguration")
    }

    override func body() -> [LayoutNode] {
        (configuration as? FlexContentConfiguration)?.content() ?? []
    }

    private func apply() {
        if let configuration = configuration as? FlexContentConfiguration { insets = configuration.insets }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }
}
#endif
