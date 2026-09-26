import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = DigitizerViewController()
        window.makeKeyAndVisible()
        self.window = window

        // Auto-lock would background the app, and iOS suspends its network
        // connections shortly after — the whole point here is to stay connected.
        application.isIdleTimerDisabled = true

        return true
    }
}
