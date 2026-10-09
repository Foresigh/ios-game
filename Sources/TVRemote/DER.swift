import Foundation

/// Minimal ASN.1 DER encoding/decoding: enough to build a self-signed X.509
/// certificate and to pull the modulus and exponent out of an RSA public key.
enum DER {
    static func tlv(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [tag]
        if content.count < 0x80 {
            out.append(UInt8(content.count))
        } else {
            var lengthBytes: [UInt8] = []
            var n = content.count
            while n > 0 {
                lengthBytes.insert(UInt8(n & 0xFF), at: 0)
                n >>= 8
            }
            out.append(0x80 | UInt8(lengthBytes.count))
            out += lengthBytes
        }
        return out + content
    }

    static func sequence(_ parts: [UInt8]...) -> [UInt8] { tlv(0x30, parts.flatMap { $0 }) }
    static func set(_ parts: [UInt8]...) -> [UInt8] { tlv(0x31, parts.flatMap { $0 }) }
    static func explicit(_ tagNumber: UInt8, _ content: [UInt8]) -> [UInt8] { tlv(0xA0 | tagNumber, content) }
    static func oid(_ encoded: [UInt8]) -> [UInt8] { tlv(0x06, encoded) }
    static func utf8(_ s: String) -> [UInt8] { tlv(0x0C, Array(s.utf8)) }
    static func bitString(_ bytes: [UInt8]) -> [UInt8] { tlv(0x03, [0] + bytes) }
    static let null: [UInt8] = [0x05, 0x00]

    /// A positive INTEGER (adds the 0x00 sign byte DER needs when the top bit is set).
    static func integer(_ bytes: [UInt8]) -> [UInt8] {
        tlv(0x02, (bytes.first ?? 0) >= 0x80 ? [0] + bytes : bytes)
    }

    static func utcTime(_ date: Date) -> [UInt8] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyMMddHHmmss'Z'"
        return tlv(0x17, Array(f.string(from: date).utf8))
    }

    static func generalizedTime(_ s: String) -> [UInt8] { tlv(0x18, Array(s.utf8)) }

    /// Reads the element at `start`: its tag, its content, and the index just past it.
    static func read(_ b: [UInt8], at start: Int) -> (tag: UInt8, content: ArraySlice<UInt8>, end: Int)? {
        var i = start
        guard i + 2 <= b.count else { return nil }
        let tag = b[i]
        var length = Int(b[i + 1])
        i += 2
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard count > 0, count <= 4, i + count <= b.count else { return nil }
            length = 0
            for _ in 0..<count {
                length = length << 8 | Int(b[i])
                i += 1
            }
        }
        guard i + length <= b.count else { return nil }
        return (tag, b[i..<i + length], i + length)
    }

    /// Modulus and exponent of a PKCS#1 RSAPublicKey (what SecKeyCopyExternalRepresentation
    /// returns), without DER's leading zero bytes — the form the pairing hash uses.
    static func rsaPublicKey(_ pkcs1: [UInt8]) -> (modulus: [UInt8], exponent: [UInt8])? {
        guard let seq = read(pkcs1, at: 0), seq.tag == 0x30 else { return nil }
        let inner = Array(seq.content)
        guard let n = read(inner, at: 0), n.tag == 0x02,
              let e = read(inner, at: n.end), e.tag == 0x02 else { return nil }
        return (Array(n.content.drop(while: { $0 == 0 })), Array(e.content.drop(while: { $0 == 0 })))
    }
}
