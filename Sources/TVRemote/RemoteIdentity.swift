import Foundation
import Security

struct RemoteError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// The iPad's own TLS client certificate. A Google TV remembers each paired
/// remote by its certificate, so this is generated once and kept in the
/// keychain for good — the app's keychain holds nothing else.
enum RemoteIdentity {
    struct Loaded {
        let identity: SecIdentity
        let publicKey: (modulus: [UInt8], exponent: [UInt8])
    }

    private static let keyTag = "com.kayi.signalrunner.tvremote.key".data(using: .utf8)!
    private static let certLabel = "Signal Runner TV Remote"

    /// Slow the first time (2048-bit RSA key generation), so call it off the main thread.
    static func loadOrCreate() throws -> Loaded {
        if let existing = load() { return existing }
        try create()
        guard let created = load() else { throw RemoteError("Couldn't save the remote's certificate on this iPad.") }
        return created
    }

    private static func load() -> Loaded? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var ref: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &ref) == errSecSuccess, let found = ref else { return nil }
        let identity = found as! SecIdentity

        var privateKey: SecKey?
        guard SecIdentityCopyPrivateKey(identity, &privateKey) == errSecSuccess,
              let key = privateKey,
              let publicKey = SecKeyCopyPublicKey(key),
              let pkcs1 = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?,
              let parts = DER.rsaPublicKey(Array(pkcs1)) else { return nil }
        return Loaded(identity: identity, publicKey: parts)
    }

    private static func create() throws {
        // Clear out anything half-made by an earlier failed attempt.
        let oldKey: [String: Any] = [kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: keyTag]
        let oldCertificate: [String: Any] = [kSecClass as String: kSecClassCertificate, kSecAttrLabel as String: certLabel]
        SecItemDelete(oldKey as CFDictionary)
        SecItemDelete(oldCertificate as CFDictionary)

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag,
            ],
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              let pkcs1 = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw RemoteError("Couldn't create the remote's security key.")
        }

        let sha256WithRSA = DER.sequence(DER.oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]), DER.null)
        let rsaEncryption = DER.sequence(DER.oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]), DER.null)
        let name = DER.sequence(DER.set(DER.sequence(DER.oid([0x55, 0x04, 0x03]), DER.utf8("atvremote"))))

        var serial = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, serial.count, &serial)
        serial[0] = (serial[0] & 0x7F) | 0x01

        let tbs = DER.sequence(
            DER.explicit(0, DER.integer([2])),                  // X.509 v3
            DER.integer(serial),
            sha256WithRSA,
            name,                                               // issuer
            DER.sequence(DER.utcTime(Date(timeIntervalSinceNow: -86_400)),
                         DER.generalizedTime("20991231235959Z")),
            name,                                               // subject
            DER.sequence(rsaEncryption, DER.bitString(Array(pkcs1)))
        )
        guard let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256,
                                                    Data(tbs) as CFData, &error) as Data? else {
            throw RemoteError("Couldn't sign the remote's certificate.")
        }
        let certificateDER = DER.sequence(tbs, sha256WithRSA, DER.bitString(Array(signature)))

        guard let certificate = SecCertificateCreateWithData(nil, Data(certificateDER) as CFData) else {
            throw RemoteError("The remote's certificate came out invalid.")
        }
        // Stored next to the private key, the keychain pairs them up into a SecIdentity.
        let item: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: certLabel,
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw RemoteError("Couldn't save the remote's certificate (error \(status)).")
        }
    }
}
