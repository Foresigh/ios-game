import Foundation
import Security

/// Talks to the Claude Messages API over plain HTTPS (there is no official
/// Swift SDK). Keeps the conversation so each request carries the full chat.
final class ClaudeClient {
    enum Failure: Error {
        case badKey
        case message(String)
    }

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let systemPrompt = """
        You are Claude, chatting with someone inside a small iPad app. Keep replies friendly, \
        clear and fairly short. The app shows plain text only, so don't use Markdown \
        (no #, **, tables or code fences); use simple line breaks and dashes for lists.
        """

    /// Past turns exactly as sent and received. Assistant turns keep the API's full
    /// `content` array unchanged so any thinking blocks are passed back as-is.
    private var history: [[String: Any]] = []
    private var task: URLSessionDataTask?
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180
        return URLSession(configuration: config)
    }()

    func reset() {
        task?.cancel()
        history = []
    }

    /// Calls back on the main queue with Claude's reply text.
    func send(_ text: String, apiKey: String, completion: @escaping (Result<String, Failure>) -> Void) {
        let userTurn: [String: Any] = ["role": "user", "content": text]
        let body: [String: Any] = [
            "model": "claude-opus-5-5",
            "max_tokens": 16000,
            "system": ClaudeClient.systemPrompt,
            "thinking": ["type": "adaptive"],
            "output_config": ["effort": "low"],
            // If Claude declines, the API retries on a suitable fallback model itself.
            "fallbacks": "default",
            "messages": history + [userTurn],
        ]

        var request = URLRequest(url: ClaudeClient.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        task = session.dataTask(with: request) { [weak self] data, response, error in
            let result = self?.handle(data: data, response: response, error: error, userTurn: userTurn)
                ?? .failure(.message("Cancelled."))
            DispatchQueue.main.async { completion(result) }
        }
        task?.resume()
    }

    /// Runs on URLSession's queue; only touches `history` on success.
    private func handle(data: Data?, response: URLResponse?, error: Error?,
                        userTurn: [String: Any]) -> Result<String, Failure> {
        if let error = error as NSError? {
            if error.code == NSURLErrorCancelled { return .failure(.message("Cancelled.")) }
            return .failure(.message("Couldn't reach Claude: \(error.localizedDescription)"))
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]

        guard status == 200, let reply = json else {
            let apiMessage = (json?["error"] as? [String: Any])?["message"] as? String
            switch status {
            case 401, 403: return .failure(.badKey)
            case 429: return .failure(.message("Too many messages right now. Wait a moment and try again."))
            case 500...599: return .failure(.message("Claude is busy right now. Try again in a minute."))
            default: return .failure(.message(apiMessage ?? "Something went wrong (error \(status))."))
            }
        }

        if reply["stop_reason"] as? String == "refusal" {
            return .failure(.message("Claude can't help with that one. Try asking something else."))
        }
        let content = reply["content"] as? [[String: Any]] ?? []
        let text = content
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        history.append(userTurn)
        history.append(["role": "assistant", "content": content])
        return .success(text.isEmpty ? "(no reply)" : text)
    }
}

/// The user's Anthropic API key, kept in the keychain (never in the app's code).
enum APIKeyStore {
    private static let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.kayi.signalrunner.claude",
        kSecAttrAccount as String: "api-key",
    ]

    static func load() -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) {
        clear()
        var item = base
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func clear() {
        SecItemDelete(base as CFDictionary)
    }
}
