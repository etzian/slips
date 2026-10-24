import Foundation

/// Why an endpoint could not read a slip. Never blocks the slip: the caller logs it and moves on.
public enum AIEndpointError: Error, Equatable, Sendable {
    /// Plain HTTP to a host the user did not mark as local.
    case insecure
    case notAURL
    case missingKey
    case unauthorized
    /// The service answered with this HTTP status.
    case http(Int)
    case network
    /// The answer was not the JSON asked for.
    case badAnswer
}

/// An Ollama server the user runs (on the LAN or their own host): `/api/chat` with the shared prompt
/// and a JSON-schema `format`, temperature 0, no streaming. Same HTTPS rule as WebDAV.
public struct OllamaAssistant: ExtractionAssistant {
    public let id = "ollama"
    public let baseURL: URL
    public let model: String
    public let localNetwork: Bool
    let transport: any HTTPTransport
    public static let requestTimeout: TimeInterval = 60
    public static let probeTimeout: TimeInterval = 3

    public init(baseURL: URL, model: String, localNetwork: Bool, transport: any HTTPTransport) {
        self.baseURL = baseURL
        self.model = model
        self.localNetwork = localNetwork
        self.transport = transport
    }

    /// From a profile's settings; nil when the address is missing or not allowed.
    public init?(settings: AIEndpointSettings, defaultModel: String, transport: any HTTPTransport) {
        guard case .success(let url) = WebDAVConfig.validate(base: settings.baseUrl ?? "", localNetwork: settings.localNetwork)
        else { return nil }
        self.init(baseURL: url, model: settings.model ?? defaultModel, localNetwork: settings.localNetwork, transport: transport)
    }

    var secure: Bool { baseURL.scheme?.lowercased() == "https" || localNetwork }

    func endpoint(_ path: String) -> URL {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + path)!
    }

    /// Reachable when `/api/tags` answers; used by the settings screen's "Test the connection".
    public func probe() async -> Reachability {
        guard secure else { return .unreachable }
        guard let r = try? await transport.send(HTTPRequest(method: "GET", url: endpoint("/api/tags"), timeout: Self.probeTimeout))
        else { return .unreachable }
        switch r.status {
        case 200..<300: return .reachable
        case 401, 403: return .needsAuth
        default: return .unreachable
        }
    }

    /// The request body: system instructions, the user message, the schema; no images, ever.
    func body(_ input: AssistantInput) throws -> Data {
        let json: [String: Any] = [
            "model": model,
            "stream": false,
            "format": AssistantPrompt.jsonSchema,
            "options": ["temperature": 0],
            "messages": [
                ["role": "system", "content": AssistantPrompt.instructions],
                ["role": "user", "content": AssistantPrompt.message(input)],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    }

    public func extract(_ input: AssistantInput) async throws -> AIExtraction {
        guard secure else { throw AIEndpointError.insecure }
        let request = HTTPRequest(method: "POST", url: endpoint("/api/chat"), headers: ["Content-Type": "application/json"],
                                  body: try body(input), timeout: Self.requestTimeout)
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            throw AIEndpointError.network
        }
        guard (200..<300).contains(response.status) else {
            throw response.status == 401 || response.status == 403 ? AIEndpointError.unauthorized : AIEndpointError.http(response.status)
        }
        struct Answer: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: response.body),
              let reading = AssistantReading.decode(answer.message.content)
        else { throw AIEndpointError.badAnswer }
        return reading.extraction(fallbackCurrency: input.currencyHint ?? "CAD")
    }
}
