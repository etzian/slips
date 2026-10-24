import Foundation

/// The Claude API (Anthropic), over raw HTTP: Swift has no official SDK. `POST /v1/messages` with the
/// shared instructions as a cached system block, the masked slip text as the user turn, and structured
/// outputs (`output_config.format`, JSON schema) so the answer is the fields and nothing else.
/// The key is the user's own, from the Keychain.
public struct ClaudeAssistant: ExtractionAssistant {
    public let id = "claude"
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let apiVersion = "2026-10-21"
    /// The smallest current model, per the execution plan (§7: smallest model that passes); P8 measures it.
    public static let defaultModel = "claude-haiku-5-5"
    public static let requestTimeout: TimeInterval = 60

    public let model: String
    let apiKey: String
    let transport: any HTTPTransport

    public init(model: String = ClaudeAssistant.defaultModel, apiKey: String, transport: any HTTPTransport) {
        self.model = model
        self.apiKey = apiKey
        self.transport = transport
    }

    /// The request body. Reading a slip is a simple task: low effort. No `temperature` (refused since
    /// API version 2026-10-21), no image, no prefill.
    func body(_ input: AssistantInput) throws -> Data {
        let json: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": [
                ["type": "text", "text": AssistantPrompt.instructions, "cache_control": ["type": "ephemeral"]],
            ],
            "messages": [
                ["role": "user", "content": AssistantPrompt.message(input)],
            ],
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": AssistantPrompt.jsonSchema],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    }

    public func extract(_ input: AssistantInput) async throws -> AIExtraction {
        guard !apiKey.isEmpty else { throw AIEndpointError.missingKey }
        let request = HTTPRequest(method: "POST", url: Self.endpoint,
                                  headers: ["x-api-key": apiKey, "anthropic-version": Self.apiVersion,
                                            "content-type": "application/json"],
                                  body: try body(input), timeout: Self.requestTimeout)
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            throw AIEndpointError.network
        }
        switch response.status {
        case 200..<300: break
        case 401: throw AIEndpointError.unauthorized
        default: throw AIEndpointError.http(response.status)
        }
        struct Answer: Decodable {
            struct Block: Decodable {
                let type: String
                let text: String?
            }
            let content: [Block]
            let stop_reason: String?
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: response.body) else { throw AIEndpointError.badAnswer }
        // A safety classifier may decline (HTTP 200, `refusal`): nothing to read, the slip stays as it is.
        guard answer.stop_reason != "refusal", answer.stop_reason != "max_tokens" else { throw AIEndpointError.badAnswer }
        guard let text = answer.content.first(where: { $0.type == "text" })?.text,
              let reading = AssistantReading.decode(text)
        else { throw AIEndpointError.badAnswer }
        return reading.extraction(fallbackCurrency: input.currencyHint ?? "CAD")
    }
}
