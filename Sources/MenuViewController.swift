import UIKit

/// The app's home screen: pick the game or the TV remote.
final class MenuViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background

        let title = UILabel(text: "SIGNAL RUNNER", size: 48, bold: true)
        let subtitle = UILabel(text: "Pick one", size: 18, color: Palette.dimText)

        let play = ActionButton("▶  PLAY GAME", style: .primary, fontSize: 26) { [weak self] in
            self?.open(GameViewController())
        }
        let remote = ActionButton("📺  TV REMOTE", fontSize: 26) { [weak self] in
            self?.open(RemoteViewController())
        }
        let horror = ActionButton("👁  THE HOUSE (HORROR)", fontSize: 26) { [weak self] in
            self?.open(HorrorViewController())
        }
        let claude = ActionButton("💬  ASK CLAUDE", fontSize: 26) { [weak self] in
            self?.open(ChatViewController())
        }

        let stack = UIStackView([title, subtitle, play, horror, remote, claude], axis: .vertical, spacing: 16)
        stack.setCustomSpacing(8, after: title)
        stack.setCustomSpacing(28, after: subtitle)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(equalToConstant: 440),
            play.heightAnchor.constraint(equalToConstant: 84),
            remote.heightAnchor.constraint(equalToConstant: 84),
            claude.heightAnchor.constraint(equalToConstant: 84),
            horror.heightAnchor.constraint(equalToConstant: 84),
        ])
    }

    private func open(_ controller: UIViewController) {
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
}
