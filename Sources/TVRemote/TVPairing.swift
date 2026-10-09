import UIKit
import CommonCrypto

/// The one-time pairing handshake on port 6467: we ask to pair, the TV shows
/// a 6-character code, and we send back a hash proving we saw it. Mirrors the
/// `androidtv-remote` npm package the PC relay used.
final class TVPairing {
    var onNeedCode: (() -> Void)?
    /// `nil` means paired successfully.
    var onFinished: ((String?) -> Void)?

    private let identity: RemoteIdentity.Loaded
    private let link: TLSLink
    private var done = false

    init(host: String, identity: RemoteIdentity.Loaded) {
        self.identity = identity
        link = TLSLink(host: host, port: 6467, identity: identity.identity)
        link.onReady = { [weak self] in
            self?.send { message in
                message.message(10) { request in
                    request.string(1, "atvremote")
                    request.string(2, UIDevice.current.name)
                }
            }
        }
        link.onMessage = { [weak self] in self?.handle($0) }
        link.onClose = { [weak self] error in
            self?.finish(error ?? "The TV ended pairing. Try again.")
        }
    }

    func start() { link.start() }

    func cancel() {
        done = true
        link.close()
    }

    /// Returns false if the code is wrong. The code's first byte is a checksum
    /// of the rest, so a typo is caught here before anything is sent.
    func submit(code: String) -> Bool {
        let hex = code.uppercased().filter { !$0.isWhitespace }
        guard hex.count == 6, let codeBytes = TVPairing.hexBytes(hex),
              let server = link.peerPublicKey else { return false }

        let input = identity.publicKey.modulus + identity.publicKey.exponent
            + server.modulus + server.exponent + Array(codeBytes[1...])
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256(input, CC_LONG(input.count), &hash)
        guard hash[0] == codeBytes[0] else { return false }

        send { message in message.message(40) { secret in secret.bytesField(1, hash) } }
        return true
    }

    private func send(_ body: (inout ProtoWriter) -> Void) {
        var message = ProtoWriter()
        message.varint(1, 2)    // protocol_version
        message.varint(2, 200)  // status: OK
        body(&message)
        link.send(message)
    }

    private func handle(_ message: ProtoMessage) {
        let status = message.varint(2) ?? 0
        guard status == 200 else {
            finish(status == 402 ? "That code didn't work. Try pairing again." : "The TV refused to pair (status \(status)).")
            return
        }
        if message.has(11) {            // pairing_request_ack → offer a 6-digit hex code
            send { message in
                message.message(20) { option in
                    option.message(1) { encoding in
                        encoding.varint(1, 3)   // ENCODING_TYPE_HEXADECIMAL
                        encoding.varint(2, 6)   // symbol_length
                    }
                    option.varint(3, 1)         // preferred_role: ROLE_TYPE_INPUT
                }
            }
        } else if message.has(20) {     // pairing_option → confirm that configuration
            send { message in
                message.message(30) { configuration in
                    configuration.message(1) { encoding in
                        encoding.varint(1, 3)
                        encoding.varint(2, 6)
                    }
                    configuration.varint(2, 1)
                }
            }
        } else if message.has(31) {     // pairing_configuration_ack → the code is on the TV now
            onNeedCode?()
        } else if message.has(41) {     // pairing_secret_ack → paired
            finish(nil)
        }
    }

    private func finish(_ error: String?) {
        guard !done else { return }
        done = true
        link.close()
        onFinished?(error)
    }

    private static func hexBytes(_ hex: String) -> [UInt8]? {
        let chars = Array(hex)
        guard chars.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let byte = UInt8(String(chars[i...i + 1]), radix: 16) else { return nil }
            bytes.append(byte)
        }
        return bytes
    }
}
