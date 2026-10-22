import UIKit

/// iOS 27 requires scene-based lifecycle; an app that creates its window in the app delegate crashes at launch.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let tabs = UITabBarController()
        tabs.viewControllers = [
            nav(ProfileViewController(), "Profile", "person.crop.circle"),
            nav(GalleryViewController(), "Gallery", "square.grid.3x3"),
            nav(FeedViewController(), "Feed", "text.bubble"),
            nav(FormViewController(), "Form", "switch.2"),
            nav(makeSwiftUIDemoController(), "SwiftUI", "swift"),
        ]
        // `-tab 2` and `-rtl YES` launch arguments make screenshots reproducible.
        tabs.selectedIndex = UserDefaults.standard.integer(forKey: "tab")
        if UserDefaults.standard.bool(forKey: "rtl") { Direction.apply(.forceRightToLeft, to: tabs.view) }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        self.window = window
    }

    private func nav(_ controller: UIViewController, _ title: String, _ symbol: String) -> UINavigationController {
        controller.title = title
        let nav = UINavigationController(rootViewController: controller)
        nav.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: symbol), selectedImage: nil)
        return nav
    }
}
