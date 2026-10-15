import UIKit

// UIKit apps must adopt the scene lifecycle (enforced from iOS 26); the
// window is created here rather than in AppDelegate.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = DigitizerViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}
