import Foundation

/// Talks to the Moonlit server, which holds the Claude API key and streams readings back.
/// The app never sees an Anthropic key.
struct ReadingClient {
    /// Default server: the deployed Moonlit server on Railway.
    static let defaultServerURL = "https://moonlit-server-production.up.railway.app"
    /// A server running on this Mac (`npm run dev`); the simulator reaches it directly.
    static let localServerURL = "http://localhost:8787"
    /// Optional shared key; must match MOONLIT_APP_KEY on the server if that is set.
    static let appKey = ""

    struct Turn: Encodable { let role: String; let content: String }

    private struct Body: Encodable {
        let psychicId: String
        let userName: String
        let sign: String?
        let messages: [Turn]
    }

    struct ServerError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    let baseURL: URL
    let deviceID: String

    func health() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.timeoutInterval = 6
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func stream(psychicID: String, userName: String, sign: String?, turns: [Turn],
                onText: @escaping @MainActor (String) -> Void) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/reading"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(deviceID, forHTTPHeaderField: "x-device-id")
        if !Self.appKey.isEmpty { request.setValue(Self.appKey, forHTTPHeaderField: "x-moonlit-key") }
        request.httpBody = try JSONEncoder().encode(Body(psychicId: psychicID, userName: userName, sign: sign, messages: turns))

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            throw ServerError(message: "Can't reach the spirits right now. Check your connection and try again.")
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status != 200 {
            var raw = ""
            for try await line in bytes.lines { raw += line; if raw.count > 4000 { break } }
            throw ServerError(message: Self.message(fromJSON: raw) ?? "The reading couldn't start (error \(status)).")
        }

        var finished = false
        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { continue }
            switch type {
            case "text":
                if let text = event["text"] as? String { await onText(text) }
            case "done":
                finished = true
            case "error":
                throw ServerError(message: event["message"] as? String ?? "The reading was interrupted.")
            default:
                break
            }
        }
        if !finished { throw ServerError(message: "The reading was interrupted.") }
    }

    private static func message(fromJSON raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["message"] as? String
    }
}
