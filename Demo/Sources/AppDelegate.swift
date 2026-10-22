import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        true
    }
}

enum Direction {
    /// `effectiveUserInterfaceLayoutDirection` follows each view's own attribute, so set it down the tree.
    @MainActor
    static func apply(_ attribute: UISemanticContentAttribute, to view: UIView) {
        view.semanticContentAttribute = attribute
        view.subviews.forEach { apply(attribute, to: $0) }
        view.setNeedsLayout()
    }
}
