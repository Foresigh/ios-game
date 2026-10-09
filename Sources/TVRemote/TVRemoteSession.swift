import UIKit

/// Android key codes the remote screen sends.
enum TVKey: UInt64 {
    case home = 3, back = 4
    case up = 19, down = 20, left = 21, right = 22, center = 23
    case volumeUp = 24, volumeDown = 25, power = 26
    case playPause = 85, next = 87, previous = 88
    case mute = 164, settings = 176
}

/// The everyday control connection on port 6466, used after pairing. The TV
/// drives the handshake; we answer its configure / set-active / ping messages.
final class TVRemoteSession {
    var onReady: (() -> Void)?
    var onVolume: ((_ level: UInt64, _ max: UInt64, _ muted: Bool) -> Void)?
    /// `nil` means the TV closed the connection normally.
    var onClose: ((String?) -> Void)?

    private let link: TLSLink

    init(host: String, identity: SecIdentity) {
        link = TLSLink(host: host, port: 6466, identity: identity)
        link.onMessage = { [weak self] in self?.handle($0) }
        link.onClose = { [weak self] in self?.onClose?($0) }
    }

    func start() { link.start() }
    func close() { link.close() }

    func press(_ key: TVKey) {
        var message = ProtoWriter()
        message.message(10) { inject in
            inject.varint(1, key.rawValue)
            inject.varint(2, 3)     // direction: SHORT press
        }
        link.send(message)
    }

    func openLink(_ url: String) {
        var message = ProtoWriter()
        message.message(90) { launch in launch.string(1, url) }
        link.send(message)
    }

    private func handle(_ message: ProtoMessage) {
        if message.has(1) {                             // remote_configure
            var reply = ProtoWriter()
            reply.message(1) { configure in
                configure.varint(1, 622)
                configure.message(2) { device in
                    device.string(1, UIDevice.current.model)
                    device.string(2, "Apple")
                    device.varint(3, 1)
                    device.string(4, "1")
                    device.string(5, "atvremote")
                    device.string(6, "1.0.0")
                }
            }
            link.send(reply)
            onReady?()
        } else if message.has(2) {                      // remote_set_active
            var reply = ProtoWriter()
            reply.message(2) { active in active.varint(1, 622) }
            link.send(reply)
        } else if let ping = message.message(8) {       // remote_ping_request
            var reply = ProtoWriter()
            reply.message(9) { pong in pong.varint(1, ping.varint(1) ?? 0) }
            link.send(reply)
        } else if let volume = message.message(50) {    // remote_set_volume_level
            onVolume?(volume.varint(7) ?? 0, volume.varint(6) ?? 0, volume.varint(8) == 1)
        }
    }
}
