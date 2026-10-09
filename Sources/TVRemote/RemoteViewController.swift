import UIKit

/// Google TV remote: pairs once with the TV, then sends button presses to it
/// directly over Wi-Fi. No PC or relay server involved.
final class RemoteViewController: UIViewController, UITextFieldDelegate {

    private enum Keys {
        static let host = "tvRemote.host"
        static let paired = "tvRemote.paired"
    }

    private var savedHost: String? {
        get { UserDefaults.standard.string(forKey: Keys.host) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.host) }
    }
    private var isPaired: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.paired) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.paired) }
    }

    private var identity: RemoteIdentity.Loaded?
    private var pairing: TVPairing?
    private var session: TVRemoteSession?
    private var sessionIsReady = false
    private var isVisible = false

    private let statusLabel = UILabel(text: "", size: 18, color: Palette.dimText)
    private let spinner = UIActivityIndicatorView(style: .whiteLarge)
    private let hostField = UITextField()
    private let codeField = UITextField()
    private let setupMessage = UILabel(text: "", size: 16, color: Palette.error)
    private let codeMessage = UILabel(text: "", size: 16, color: Palette.error)
    private var setupPanel: UIStackView!
    private var codePanel: UIStackView!
    private var remotePanel: UIStackView!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        buildUI()

        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)

        if isPaired, let host = savedHost {
            connectRemote(host)
        } else {
            showSetup(message: nil)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// The connection drops while the iPad sleeps; pick it back up on return.
    @objc private func appBecameActive() {
        guard isVisible, session == nil, pairing == nil, isPaired, let host = savedHost else { return }
        connectRemote(host)
    }

    private func close() {
        pairing?.cancel()
        pairing = nil
        session?.close()
        session = nil
        dismiss(animated: true)
    }

    // MARK: - Flow

    private func connectTapped() {
        let host = (hostField.text ?? "").trimmingCharacters(in: .whitespaces)
        guard isIPAddress(host) else {
            setupMessage.text = "Type the TV's IP address, like 192.168.1.42"
            return
        }
        view.endEditing(true)
        if isPaired && host == savedHost {
            connectRemote(host)
        } else {
            savedHost = host
            isPaired = false
            startPairing(host)
        }
    }

    private func startPairing(_ host: String) {
        withIdentity { [weak self] identity in
            guard let self = self else { return }
            self.showBusy("Asking the TV to pair… look at the TV.")
            let pairing = TVPairing(host: host, identity: identity)
            pairing.onNeedCode = { [weak self] in self?.showCodeEntry() }
            pairing.onFinished = { [weak self] error in
                guard let self = self else { return }
                self.pairing = nil
                if let error = error {
                    self.showSetup(message: error)
                    return
                }
                self.isPaired = true
                self.showBusy("Paired! Connecting…")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.connectRemote(host) }
            }
            self.pairing = pairing
            pairing.start()
        }
    }

    private func submitCode() {
        guard let pairing = pairing else { return }
        if pairing.submit(code: codeField.text ?? "") {
            view.endEditing(true)
            showBusy("Checking the code…")
        } else {
            codeMessage.text = "That's not the code on the TV. It's 6 letters/numbers — check and try again."
        }
    }

    private func connectRemote(_ host: String) {
        withIdentity { [weak self] identity in
            guard let self = self else { return }
            self.session?.close()
            self.sessionIsReady = false
            self.showBusy("Connecting to the TV at \(host)…")

            let session = TVRemoteSession(host: host, identity: identity.identity)
            session.onReady = { [weak self] in
                self?.sessionIsReady = true
                self?.show(self?.remotePanel)
                self?.statusLabel.text = "Connected to the TV"
            }
            session.onVolume = { [weak self] level, max, muted in
                self?.statusLabel.text = muted ? "Connected · muted" : "Connected · volume \(level) of \(max)"
            }
            session.onClose = { [weak self] error in
                guard let self = self else { return }
                let wasReady = self.sessionIsReady
                self.session = nil
                self.sessionIsReady = false
                if wasReady {
                    // Dropped mid-use (TV went to sleep, Wi-Fi blip): try once more.
                    self.showBusy("Lost the TV, reconnecting…")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if self.isVisible && self.session == nil { self.connectRemote(host) }
                    }
                } else {
                    // Never got going. Either the TV is off, or it has forgotten this
                    // iPad — so the next Connect tap pairs again, which fixes both.
                    self.isPaired = false
                    let reason = error ?? "The TV closed the connection."
                    self.showSetup(message: "\(reason)\nMake sure the TV is on, then tap Connect to pair again.")
                }
            }
            self.session = session
            session.start()
        }
    }

    private func pairDifferentTV() {
        session?.close()
        session = nil
        isPaired = false
        showSetup(message: nil)
    }

    /// The certificate is made once (a few seconds on an old iPad), then reused.
    private func withIdentity(_ then: @escaping (RemoteIdentity.Loaded) -> Void) {
        if let identity = identity {
            then(identity)
            return
        }
        showBusy("Setting this iPad up as a remote (first time only)…")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let loaded = try RemoteIdentity.loadOrCreate()
                DispatchQueue.main.async {
                    self.identity = loaded
                    then(loaded)
                }
            } catch {
                DispatchQueue.main.async { self.showSetup(message: error.localizedDescription) }
            }
        }
    }

    private func isIPAddress(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
    }

    // MARK: - Screens

    private func show(_ panel: UIView?) {
        [setupPanel, codePanel, remotePanel].forEach { $0?.isHidden = $0 !== panel }
        if panel == nil { spinner.startAnimating() } else { spinner.stopAnimating() }
    }

    private func showBusy(_ status: String) {
        statusLabel.text = status
        show(nil)
    }

    private func showSetup(message: String?) {
        statusLabel.text = "Not connected"
        setupMessage.text = message
        hostField.text = savedHost
        show(setupPanel)
    }

    private func showCodeEntry() {
        statusLabel.text = "The TV is showing a code"
        codeMessage.text = nil
        codeField.text = ""
        show(codePanel)
        codeField.becomeFirstResponder()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === hostField { connectTapped() } else { submitCode() }
        return false
    }

    // MARK: - Layout

    private func buildUI() {
        let back = ActionButton("‹ MENU") { [weak self] in self?.close() }
        let title = UILabel(text: "TV REMOTE", size: 28, bold: true)

        setupPanel = buildSetupPanel()
        codePanel = buildCodePanel()
        remotePanel = buildRemotePanel()
        spinner.hidesWhenStopped = true

        let guide = view.safeAreaLayoutGuide
        for v in [back, title, statusLabel, spinner, setupPanel!, codePanel!, remotePanel!] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        NSLayoutConstraint.activate([
            back.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            back.topAnchor.constraint(equalTo: guide.topAnchor, constant: 20),
            back.widthAnchor.constraint(equalToConstant: 120),
            back.heightAnchor.constraint(equalToConstant: 48),
            title.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: back.centerYAnchor),

            statusLabel.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),

            spinner.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 40),

            setupPanel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 24),
            setupPanel.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            setupPanel.widthAnchor.constraint(equalToConstant: 520),

            codePanel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 24),
            codePanel.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            codePanel.widthAnchor.constraint(equalToConstant: 520),

            remotePanel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 20),
            remotePanel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 30),
            remotePanel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -30),
            remotePanel.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -30),
        ])
    }

    private func styleField(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.font = UIFont.boldSystemFont(ofSize: 26)
        field.textAlignment = .center
        field.borderStyle = .roundedRect
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.delegate = self
        field.heightAnchor.constraint(equalToConstant: 56).isActive = true
    }

    private func buildSetupPanel() -> UIStackView {
        let heading = UILabel(text: "Pair with your Google TV", size: 24, bold: true)
        let help = UILabel(text: "Find the TV's IP address on the TV: Settings → Network & Internet → your Wi-Fi network. The iPad and the TV must be on the same Wi-Fi.",
                           size: 16, color: Palette.dimText)
        styleField(hostField, placeholder: "192.168.1.42")
        hostField.keyboardType = .numbersAndPunctuation
        hostField.returnKeyType = .go
        let connect = ActionButton("CONNECT", style: .primary) { [weak self] in self?.connectTapped() }
        connect.heightAnchor.constraint(equalToConstant: 56).isActive = true
        return UIStackView([heading, help, hostField, connect, setupMessage], axis: .vertical, spacing: 16)
    }

    private func buildCodePanel() -> UIStackView {
        let heading = UILabel(text: "Type the code shown on the TV", size: 24, bold: true)
        styleField(codeField, placeholder: "A1B2C3")
        codeField.autocapitalizationType = .allCharacters
        codeField.returnKeyType = .done
        let submit = ActionButton("PAIR", style: .primary) { [weak self] in self?.submitCode() }
        submit.heightAnchor.constraint(equalToConstant: 56).isActive = true
        let cancel = ActionButton("CANCEL") { [weak self] in
            self?.pairing?.cancel()
            self?.pairing = nil
            self?.showSetup(message: nil)
        }
        return UIStackView([heading, codeField, submit, cancel, codeMessage], axis: .vertical, spacing: 16)
    }

    private func buildRemotePanel() -> UIStackView {
        let key: (String, TVKey, ActionButton.Style) -> ActionButton = { title, code, style in
            ActionButton(title, style: style, fontSize: 22) { [weak self] in self?.session?.press(code) }
        }

        // D-pad: a 3×3 grid with blanks in the corners.
        let dpadRows: [[UIView]] = [
            [UIView(), key("▲", .up, .secondary), UIView()],
            [key("◀", .left, .secondary), key("OK", .center, .primary), key("▶", .right, .secondary)],
            [UIView(), key("▼", .down, .secondary), UIView()],
        ]
        let dpad = UIStackView(dpadRows.map { UIStackView($0, axis: .horizontal, spacing: 12, distribution: .fillEqually) },
                               axis: .vertical, spacing: 12, distribution: .fillEqually)
        dpad.widthAnchor.constraint(equalToConstant: 330).isActive = true
        dpad.heightAnchor.constraint(equalToConstant: 330).isActive = true

        let open: (String, String) -> ActionButton = { title, url in
            ActionButton(title, fontSize: 18) { [weak self] in self?.session?.openLink(url) }
        }
        let rows: [[UIView]] = [
            [key("‹ BACK", .back, .secondary), key("HOME", .home, .secondary), key("⏻ POWER", .power, .secondary)],
            [key("VOL −", .volumeDown, .secondary), key("MUTE", .mute, .secondary), key("VOL +", .volumeUp, .secondary)],
            [key("⏮", .previous, .secondary), key("⏯ PLAY / PAUSE", .playPause, .secondary), key("⏭", .next, .secondary)],
            [open("YOUTUBE", "https://www.youtube.com"), open("NETFLIX", "https://www.netflix.com/title"),
             key("SETTINGS", .settings, .secondary)],
            [ActionButton("PAIR A DIFFERENT TV", fontSize: 15) { [weak self] in self?.pairDifferentTV() }],
        ]
        let buttons = UIStackView(rows.map { UIStackView($0, axis: .horizontal, spacing: 12, distribution: .fillEqually) },
                                  axis: .vertical, spacing: 12, distribution: .fillEqually)

        let panel = UIStackView([dpad, buttons], axis: .horizontal, spacing: 40)
        panel.alignment = .center
        buttons.heightAnchor.constraint(equalTo: panel.heightAnchor).isActive = true
        return panel
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
}
