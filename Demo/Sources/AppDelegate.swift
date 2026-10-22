import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let tabs = UITabBarController()
        tabs.viewControllers = [
            nav(ProfileViewController(), "Profile", "person.crop.circle"),
            nav(GalleryViewController(), "Gallery", "square.grid.3x3"),
            nav(FeedViewController(), "Feed", "text.bubble"),
            nav(FormViewController(), "Form", "switch.2"),
        ]
        // `-tab 2` and `-rtl YES` launch arguments make screenshots reproducible.
        tabs.selectedIndex = UserDefaults.standard.integer(forKey: "tab")
        if UserDefaults.standard.bool(forKey: "rtl") { Direction.apply(.forceRightToLeft, to: tabs.view) }

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    private func nav(_ controller: UIViewController, _ title: String, _ symbol: String) -> UINavigationController {
        controller.title = title
        let nav = UINavigationController(rootViewController: controller)
        nav.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: symbol), selectedImage: nil)
        return nav
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
