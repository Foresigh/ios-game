import Foundation
import Network
import Security

/// One TLS connection to the TV: presents our client certificate, accepts
/// the TV's self-signed one (Google TVs never have a CA-signed certificate),
/// and turns the byte stream into protobuf messages. Callbacks run on main.
final class TLSLink {
    var onReady: (() -> Void)?
    var onMessage: ((ProtoMessage) -> Void)?
    /// `nil` means the TV closed the connection normally.
    var onClose: ((String?) -> Void)?

    /// The TV's RSA public key, captured during the handshake (pairing needs it).
    private(set) var peerPublicKey: (modulus: [UInt8], exponent: [UInt8])?

    private let host: String
    private let port: UInt16
    private let identity: SecIdentity
    private let queue = DispatchQueue(label: "com.kayi.signalrunner.tvremote")
    private var connection: NWConnection?
    private var reader = ProtoFrameReader()
    private var finished = false
    private var isReady = false

    init(host: String, port: UInt16, identity: SecIdentity) {
        self.host = host
        self.port = port
        self.identity = identity
    }

    func start() {
        let tls = NWProtocolTLS.Options()
        let security = tls.securityProtocolOptions
        if let local = sec_identity_create(identity) {
            sec_protocol_options_set_local_identity(security, local)
        }
        sec_protocol_options_set_verify_block(security, { [weak self] _, trust, complete in
            let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            if let certificate = SecTrustGetCertificateAtIndex(secTrust, 0),
               let key = SecCertificateCopyKey(certificate),
               let pkcs1 = SecKeyCopyExternalRepresentation(key, nil) as Data? {
                self?.peerPublicKey = DER.rsaPublicKey(Array(pkcs1))
            }
            complete(true)
        }, queue)

        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: NWParameters(tls: tls))
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.isReady = true
                DispatchQueue.main.async { self.onReady?() }
                self.receive()
            case .waiting(let error), .failed(let error):
                self.finish(TLSLink.describe(error))
            case .cancelled:
                self.finish(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)

        // NWConnection can sit in "preparing" for a long time when nothing answers.
        queue.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self, !self.isReady else { return }
            self.finish("Couldn't reach the TV at \(self.host). Check that it's on and on the same Wi-Fi.")
        }
    }

    func send(_ message: ProtoWriter) {
        let data = message.delimited
        queue.async { self.connection?.send(content: data, completion: .contentProcessed { _ in }) }
    }

    /// Closes without reporting back through `onClose`.
    func close() {
        onReady = nil
        onMessage = nil
        onClose = nil
        queue.async {
            self.finished = true
            self.connection?.cancel()
        }
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                let messages = self.reader.append(data)
                DispatchQueue.main.async { messages.forEach { self.onMessage?($0) } }
            }
            if let error = error {
                self.finish(TLSLink.describe(error))
            } else if isComplete {
                self.finish(nil)
            } else {
                self.receive()
            }
        }
    }

    /// Runs on `queue`.
    private func finish(_ error: String?) {
        guard !finished else { return }
        finished = true
        connection?.cancel()
        DispatchQueue.main.async { self.onClose?(error) }
    }

    private static func describe(_ error: NWError) -> String {
        switch error {
        case .posix(let code) where code == .ECONNREFUSED:
            return "The TV refused the connection."
        case .tls(_):
            return "The TV rejected this iPad's security certificate."
        default:
            return error.localizedDescription
        }
    }
}
