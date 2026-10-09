import Foundation

/// Just enough protobuf for the Android TV remote protocol: varints and
/// length-delimited fields, no schema compiler or third-party library needed.
struct ProtoWriter {
    private(set) var bytes: [UInt8] = []

    mutating func varint(_ field: Int, _ value: UInt64) {
        ProtoWriter.appendVarint(&bytes, UInt64(field << 3))
        ProtoWriter.appendVarint(&bytes, value)
    }

    mutating func bytesField(_ field: Int, _ value: [UInt8]) {
        ProtoWriter.appendVarint(&bytes, UInt64(field << 3 | 2))
        ProtoWriter.appendVarint(&bytes, UInt64(value.count))
        bytes += value
    }

    mutating func string(_ field: Int, _ value: String) {
        bytesField(field, Array(value.utf8))
    }

    mutating func message(_ field: Int, _ build: (inout ProtoWriter) -> Void) {
        var inner = ProtoWriter()
        build(&inner)
        bytesField(field, inner.bytes)
    }

    /// The message prefixed with its length, as protobuf's encodeDelimited does.
    var delimited: Data {
        var out: [UInt8] = []
        ProtoWriter.appendVarint(&out, UInt64(bytes.count))
        return Data(out + bytes)
    }

    static func appendVarint(_ out: inout [UInt8], _ value: UInt64) {
        var v = value
        while v >= 0x80 {
            out.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        out.append(UInt8(v))
    }
}

/// A decoded message. Only the first occurrence of each field is kept, which
/// is all this protocol ever needs.
struct ProtoMessage {
    private var varints: [Int: UInt64] = [:]
    private var blobs: [Int: [UInt8]] = [:]

    init?(_ bytes: [UInt8]) {
        var i = 0
        while i < bytes.count {
            guard let key = ProtoMessage.readVarint(bytes, &i) else { return nil }
            let field = Int(key >> 3)
            switch key & 7 {
            case 0:
                guard let v = ProtoMessage.readVarint(bytes, &i) else { return nil }
                if varints[field] == nil { varints[field] = v }
            case 2:
                guard let len = ProtoMessage.readVarint(bytes, &i),
                      len <= UInt64(bytes.count - i) else { return nil }
                if blobs[field] == nil { blobs[field] = Array(bytes[i..<i + Int(len)]) }
                i += Int(len)
            case 1: i += 8
            case 5: i += 4
            default: return nil
            }
        }
        if i > bytes.count { return nil }
    }

    func has(_ field: Int) -> Bool { varints[field] != nil || blobs[field] != nil }
    func varint(_ field: Int) -> UInt64? { varints[field] }
    func message(_ field: Int) -> ProtoMessage? { blobs[field].flatMap { ProtoMessage($0) } }
    func string(_ field: Int) -> String? { blobs[field].flatMap { String(bytes: $0, encoding: .utf8) } }

    static func readVarint(_ bytes: [UInt8], _ i: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while i < bytes.count && shift < 64 {
            let byte = bytes[i]
            i += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        return nil
    }
}

/// Splits a TCP byte stream into length-prefixed protobuf messages, holding
/// on to any partial message until the rest of it arrives.
struct ProtoFrameReader {
    private var buffer: [UInt8] = []

    mutating func append(_ data: Data) -> [ProtoMessage] {
        buffer += data
        var messages: [ProtoMessage] = []
        while true {
            var i = 0
            guard let len = ProtoMessage.readVarint(buffer, &i),
                  len <= UInt64(buffer.count - i) else { break }
            let end = i + Int(len)
            if let message = ProtoMessage(Array(buffer[i..<end])) { messages.append(message) }
            buffer.removeFirst(end)
        }
        return messages
    }
}
