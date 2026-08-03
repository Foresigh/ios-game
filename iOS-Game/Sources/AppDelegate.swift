import UIKit

/// Classic AppDelegate-only lifecycle, no SceneDelegate, no storyboard.
/// This keeps the whole app buildable from a spec-generated Xcode project
/// (via XcodeGen in CI) with no Interface Builder files to get wrong.
@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = GameViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
