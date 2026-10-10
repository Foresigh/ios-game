import UIKit

/// A simple chat with Claude.
final class ChatViewController: UIViewController, UITextFieldDelegate {

    private let client = ClaudeClient()
    private var isWaiting = false

    private let scrollView = UIScrollView()
    private let messages = UIStackView([], axis: .vertical, spacing: 12)
    private let inputField = UITextField()
    private var sendButton: ActionButton!
    private var inputBar: UIStackView!
    private var inputBottom: NSLayoutConstraint!

    private var keyPanel: UIStackView!
    private let keyField = UITextField()
    private let keyMessage = UILabel(text: "", size: 16, color: Palette.error)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        buildUI()

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChange(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)

        if APIKeyStore.load() == nil {
            showKeyPanel(message: nil)
        } else {
            showChat()
            addBubble("Hi! I'm Claude. Ask me anything.", fromUser: false)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func keyboardWillChange(_ note: Notification) {
        guard let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let overlap = max(0, view.bounds.maxY - view.convert(frame, from: nil).minY)
        inputBottom.constant = -(overlap + 16)
        let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
            self.scrollToBottom()
        }
    }

    // MARK: - Chat

    private func sendTapped() {
        let text = (inputField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWaiting, let key = APIKeyStore.load() else { return }
        inputField.text = ""
        addBubble(text, fromUser: true)
        let pending = addBubble("Claude is thinking…", fromUser: false)
        pending.alpha = 0.6
        setWaiting(true)

        client.send(text, apiKey: key) { [weak self] result in
            guard let self = self else { return }
            self.setWaiting(false)
            pending.alpha = 1
            switch result {
            case .success(let reply):
                pending.text = reply
            case .failure(.badKey):
                pending.text = "That API key didn't work."
                self.showKeyPanel(message: "Claude didn't accept that key. Check it and paste it again.")
            case .failure(.message(let message)):
                pending.text = message
                pending.textColor = Palette.error
            }
            self.scrollToBottom()
        }
    }

    private func newChat() {
        client.reset()
        setWaiting(false)
        messages.arrangedSubviews.forEach { $0.removeFromSuperview() }
        addBubble("New chat started. What would you like to talk about?", fromUser: false)
    }

    private func setWaiting(_ waiting: Bool) {
        isWaiting = waiting
        sendButton.isEnabled = !waiting
        sendButton.alpha = waiting ? 0.4 : 1
    }

    /// Adds a message bubble and returns its label so a reply can fill it in later.
    @discardableResult
    private func addBubble(_ text: String, fromUser: Bool) -> UILabel {
        let label = UILabel(text: text, size: 19, color: fromUser ? Palette.accentText : Palette.text)
        label.textAlignment = .left

        let bubble = UIView()
        bubble.backgroundColor = fromUser ? Palette.accent : Palette.secondary
        bubble.layer.cornerRadius = 16
        let row = UIView()
        for (child, parent) in [(label, bubble), (bubble, row)] {
            child.translatesAutoresizingMaskIntoConstraints = false
            parent.addSubview(child)
        }
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -12),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -16),
            bubble.topAnchor.constraint(equalTo: row.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: row.widthAnchor, multiplier: 0.75),
            fromUser ? bubble.trailingAnchor.constraint(equalTo: row.trailingAnchor)
                     : bubble.leadingAnchor.constraint(equalTo: row.leadingAnchor),
        ])
        messages.addArrangedSubview(row)
        view.layoutIfNeeded()
        scrollToBottom()
        return label
    }

    private func scrollToBottom() {
        scrollView.layoutIfNeeded()
        let bottom = scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom
        if bottom > 0 { scrollView.setContentOffset(CGPoint(x: 0, y: bottom), animated: false) }
    }

    // MARK: - API key

    private func showKeyPanel(message: String?) {
        keyMessage.text = message
        keyField.text = ""
        keyPanel.isHidden = false
        scrollView.isHidden = true
        inputBar.isHidden = true
        keyField.becomeFirstResponder()
    }

    private func showChat() {
        keyPanel.isHidden = true
        scrollView.isHidden = false
        inputBar.isHidden = false
    }

    private func saveKeyTapped() {
        let key = (keyField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sk-ant-") else {
            keyMessage.text = "That doesn't look like an Anthropic API key. It starts with sk-ant-"
            return
        }
        APIKeyStore.save(key)
        view.endEditing(true)
        showChat()
        if messages.arrangedSubviews.isEmpty {
            addBubble("Key saved! I'm Claude. Ask me anything.", fromUser: false)
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === keyField { saveKeyTapped() } else { sendTapped() }
        return false
    }

    // MARK: - Layout

    private func buildUI() {
        let back = ActionButton("‹ MENU") { [weak self] in self?.dismiss(animated: true) }
        let title = UILabel(text: "ASK CLAUDE", size: 28, bold: true)
        let newChat = ActionButton("NEW CHAT", fontSize: 16) { [weak self] in self?.newChat() }
        let changeKey = ActionButton("API KEY", fontSize: 16) { [weak self] in
            self?.showKeyPanel(message: nil)
        }
        let topRight = UIStackView([newChat, changeKey], axis: .horizontal, spacing: 10, distribution: .fillEqually)

        styleField(inputField, placeholder: "Type a message…")
        inputField.returnKeyType = .send
        sendButton = ActionButton("SEND", style: .primary) { [weak self] in self?.sendTapped() }
        inputBar = UIStackView([inputField, sendButton], axis: .horizontal, spacing: 12)

        keyPanel = buildKeyPanel()
        messages.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(messages)
        scrollView.keyboardDismissMode = .interactive

        let guide = view.safeAreaLayoutGuide
        for v in [back, title, topRight, scrollView, inputBar!, keyPanel!] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        inputBottom = inputBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        NSLayoutConstraint.activate([
            back.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            back.topAnchor.constraint(equalTo: guide.topAnchor, constant: 20),
            back.widthAnchor.constraint(equalToConstant: 120),
            back.heightAnchor.constraint(equalToConstant: 48),
            title.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            topRight.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
            topRight.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            topRight.widthAnchor.constraint(equalToConstant: 250),
            topRight.heightAnchor.constraint(equalToConstant: 44),

            scrollView.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: inputBar.topAnchor, constant: -12),

            messages.topAnchor.constraint(equalTo: scrollView.topAnchor),
            messages.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            messages.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            messages.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            messages.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            inputBar.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            inputBar.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
            inputBottom,
            sendButton.widthAnchor.constraint(equalToConstant: 120),

            keyPanel.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 30),
            keyPanel.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            keyPanel.widthAnchor.constraint(equalToConstant: 560),
        ])
    }

    private func buildKeyPanel() -> UIStackView {
        let heading = UILabel(text: "Add your Claude API key", size: 24, bold: true)
        let help = UILabel(text: "Get a key at console.anthropic.com → API Keys, then paste it here. It's saved only on this iPad. Messages to Claude are charged to that account.",
                           size: 16, color: Palette.dimText)
        styleField(keyField, placeholder: "sk-ant-…")
        keyField.font = UIFont.systemFont(ofSize: 18)
        keyField.isSecureTextEntry = true
        keyField.returnKeyType = .done
        let save = ActionButton("SAVE KEY", style: .primary) { [weak self] in self?.saveKeyTapped() }
        save.heightAnchor.constraint(equalToConstant: 56).isActive = true
        return UIStackView([heading, help, keyField, save, keyMessage], axis: .vertical, spacing: 16)
    }

    private func styleField(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.font = UIFont.systemFont(ofSize: 20)
        field.borderStyle = .roundedRect
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.delegate = self
        field.heightAnchor.constraint(equalToConstant: 56).isActive = true
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
}
