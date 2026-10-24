import Foundation
import Testing
@testable import SlipsCore

/// Answers like the Messages API and keeps the requests.
final class FakeMessagesAPI: HTTPTransport, @unchecked Sendable {
    // @unchecked: `requests` is guarded by `lock`.
    private let lock = NSLock()
    private var _requests: [HTTPRequest] = []
    let status: Int
    let body: String
    var requests: [HTTPRequest] { lock.withLock { _requests } }

    init(status: Int = 200, body: String) {
        self.status = status
        self.body = body
    }

    /// A normal answer: a thinking block (empty, as by default), then the JSON text.
    static func answer(_ json: String, stop: String = "end_turn") -> String {
        let text = String(decoding: try! JSONEncoder().encode(json), as: UTF8.self)
        return #"{"id":"msg_1","type":"message","role":"assistant","content":[{"type":"thinking","thinking":""},{"type":"text","text":\#(text)}],"stop_reason":"\#(stop)","usage":{"input_tokens":1,"output_tokens":1}}"#
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock { _requests.append(request) }
        return HTTPResponse(status: status, body: Data(body.utf8))
    }

    func upload(_ request: HTTPRequest, fromFile file: URL) async throws -> HTTPResponse { HTTPResponse(status: 405) }
}

@Suite struct ClaudeTests {
    let json = #"{"merchant":"Fake Store","date":"2026-10-20","subtotal":10.00,"gst":0.50,"qst":1.00,"hst":null,"tip":null,"total":11.50,"currency":"CAD","supplier_gst_no":null,"supplier_qst_no":null,"subcategory_key":"personal.groceries"}"#
    let input = AssistantInput(ocrText: "VISA ••••1234\nTOTAL 11,50", localeIdentifier: "fr_CA", currencyHint: "CAD")

    @Test func requestShape() async throws {
        let api = FakeMessagesAPI(body: FakeMessagesAPI.answer(json))
        let reading = try await ClaudeAssistant(apiKey: "test-key", transport: api).extract(input)
        #expect(reading.total?.value == 1150)
        #expect(reading.merchant?.value == "Fake Store")
        let r = try #require(api.requests.last)
        #expect(r.url.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(r.headers["x-api-key"] == "test-key")
        #expect(r.headers["anthropic-version"] == "2026-10-21")
        let body = try #require(try JSONSerialization.jsonObject(with: r.body ?? Data()) as? [String: Any])
        #expect(body["model"] as? String == "claude-haiku-5-5")
        #expect(body["temperature"] == nil)
        #expect(body["thinking"] == nil)
        let system = try #require(body["system"] as? [[String: Any]])
        #expect((system.first?["cache_control"] as? [String: String]) == ["type": "ephemeral"])
        let config = try #require(body["output_config"] as? [String: Any])
        #expect(config["effort"] as? String == "low")
        let format = try #require(config["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 1 && messages[0]["role"] as? String == "user")
        // Text only: no image or document block, masked digits as given.
        #expect(messages[0]["content"] is String)
        #expect((messages[0]["content"] as? String)?.contains("••••1234") == true)
    }

    @Test func refusalsAndErrors() async {
        await #expect(throws: AIEndpointError.badAnswer) {
            try await ClaudeAssistant(apiKey: "k", transport: FakeMessagesAPI(body: FakeMessagesAPI.answer("", stop: "refusal"))).extract(input)
        }
        await #expect(throws: AIEndpointError.unauthorized) {
            try await ClaudeAssistant(apiKey: "bad", transport: FakeMessagesAPI(status: 401, body: #"{"type":"error"}"#)).extract(input)
        }
        await #expect(throws: AIEndpointError.http(429)) {
            try await ClaudeAssistant(apiKey: "k", transport: FakeMessagesAPI(status: 429, body: #"{"type":"error"}"#)).extract(input)
        }
        await #expect(throws: AIEndpointError.http(529)) {
            try await ClaudeAssistant(apiKey: "k", transport: FakeMessagesAPI(status: 529, body: #"{"type":"error"}"#)).extract(input)
        }
        let api = FakeMessagesAPI(body: "{}")
        await #expect(throws: AIEndpointError.missingKey) { try await ClaudeAssistant(apiKey: "", transport: api).extract(input) }
        #expect(api.requests.isEmpty)
    }

    @Test func userChosenModel() async throws {
        let api = FakeMessagesAPI(body: FakeMessagesAPI.answer(json))
        _ = try await ClaudeAssistant(model: "claude-sonnet-5-5", apiKey: "k", transport: api).extract(input)
        let body = try #require(try JSONSerialization.jsonObject(with: api.requests.last?.body ?? Data()) as? [String: Any])
        #expect(body["model"] as? String == "claude-sonnet-5-5")
    }
}
