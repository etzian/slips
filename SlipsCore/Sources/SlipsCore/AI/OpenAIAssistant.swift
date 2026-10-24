import Foundation

/// The OpenAI API, over raw HTTP: `POST /v1/responses` with the shared instructions as `instructions`
/// (OpenAI caches a repeated prefix by itself), the masked slip text as the input and a strict JSON
/// schema (`text.format`) so the answer is the fields and nothing else. `store: false`: OpenAI keeps no
/// conversation of it. The key is the user's own, from the Keychain.
public struct OpenAIAssistant: ExtractionAssistant {
    public let id = "openai"
    public static let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    /// The smallest current model, per the execution plan (§7: smallest model that passes); P8 measures it.
    public static let defaultModel = "gpt-5-mini"
    public static let requestTimeout: TimeInterval = 60

    public let model: String
    let apiKey: String
    let transport: any HTTPTransport

    public init(model: String = OpenAIAssistant.defaultModel, apiKey: String, transport: any HTTPTransport) {
        self.model = model
        self.apiKey = apiKey
        self.transport = transport
    }

    /// The request body. Reading a slip is a simple task: low reasoning effort. No `temperature`
    /// (reasoning models refuse it), no image.
    func body(_ input: AssistantInput) throws -> Data {
        let json: [String: Any] = [
            "model": model,
            "instructions": AssistantPrompt.instructions,
            "input": AssistantPrompt.message(input),
            "max_output_tokens": 16000,
            "reasoning": ["effort": "low"],
            "store": false,
            "text": [
                "format": ["type": "json_schema", "name": "slip_reading", "strict": true, "schema": AssistantPrompt.jsonSchema],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    }

    public func extract(_ input: AssistantInput) async throws -> AIExtraction {
        guard !apiKey.isEmpty else { throw AIEndpointError.missingKey }
        let request = HTTPRequest(method: "POST", url: Self.endpoint,
                                  headers: ["Authorization": "Bearer \(apiKey)", "Content-Type": "application/json"],
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
            struct Item: Decodable {
                struct Part: Decodable {
                    let type: String
                    let text: String?
                }
                let type: String
                let content: [Part]?
            }
            let status: String?
            let output: [Item]
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: response.body) else { throw AIEndpointError.badAnswer }
        // `incomplete` (out of tokens) or a `refusal` part instead of text: nothing to read, the slip stays as it is.
        guard answer.status == nil || answer.status == "completed" else { throw AIEndpointError.badAnswer }
        let parts = answer.output.filter { $0.type == "message" }.flatMap { $0.content ?? [] }
        guard !parts.contains(where: { $0.type == "refusal" }),
              let text = parts.first(where: { $0.type == "output_text" })?.text,
              let reading = AssistantReading.decode(text)
        else { throw AIEndpointError.badAnswer }
        return reading.extraction(fallbackCurrency: input.currencyHint ?? "CAD")
    }
}
