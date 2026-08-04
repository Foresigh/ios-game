import UIKit
import SpriteKit

/// No storyboard involved — the view is built entirely in code so this
/// project never needs Interface Builder / Xcode to construct correctly.
final class GameViewController: UIViewController {

    override func loadView() {
        self.view = SKView(frame: UIScreen.main.bounds)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let skView = self.view as? SKView else { return }

        let scene = GameScene(size: skView.bounds.size)
        scene.scaleMode = .resizeFill

        skView.presentScene(scene)
        skView.ignoresSiblingOrder = true
        skView.showsFPS = false
        skView.showsNodeCount = false
        skView.isMultipleTouchEnabled = false
        // Old A7/A8 GPUs: keep this off. It costs real frame time for no
        // gameplay benefit in a flat-shaded 2D scene like this one.
        skView.shouldCullNonVisibleNodes = true
    }

    override var prefersStatusBarHidden: Bool { true }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscape
    }

    override var shouldAutorotate: Bool { true }
}
