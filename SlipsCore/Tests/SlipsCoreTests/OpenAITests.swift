import Foundation
import Testing
@testable import SlipsCore

/// Answers like the Responses API and keeps the requests.
final class FakeResponsesAPI: HTTPTransport, @unchecked Sendable {
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

    /// A normal answer: a reasoning item, then the message with the JSON text (or a refusal part).
    static func answer(_ json: String, status: String = "completed", refusal: Bool = false) -> String {
        let text = String(decoding: try! JSONEncoder().encode(json), as: UTF8.self)
        let part = refusal ? #"{"type":"refusal","refusal":"no"}"# : #"{"type":"output_text","text":\#(text),"annotations":[]}"#
        return #"{"id":"resp_1","object":"response","status":"\#(status)","output":[{"id":"rs_1","type":"reasoning","summary":[]},{"id":"msg_1","type":"message","role":"assistant","content":[\#(part)]}]}"#
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock { _requests.append(request) }
        return HTTPResponse(status: status, body: Data(body.utf8))
    }

    func upload(_ request: HTTPRequest, fromFile file: URL) async throws -> HTTPResponse { HTTPResponse(status: 405) }
}

@Suite struct OpenAITests {
    let json = #"{"merchant":"Fake Store","date":"2026-10-20","subtotal":10.00,"gst":0.50,"qst":1.00,"hst":null,"tip":null,"total":11.50,"currency":"CAD","supplier_gst_no":null,"supplier_qst_no":null,"subcategory_key":"personal.groceries"}"#
    let input = AssistantInput(ocrText: "VISA ••••1234\nTOTAL 11,50", localeIdentifier: "fr_CA", currencyHint: "CAD")

    @Test func requestShape() async throws {
        let api = FakeResponsesAPI(body: FakeResponsesAPI.answer(json))
        let reading = try await OpenAIAssistant(apiKey: "test-key", transport: api).extract(input)
        #expect(reading.total?.value == 1150)
        #expect(reading.merchant?.value == "Fake Store")
        let r = try #require(api.requests.last)
        #expect(r.url.absoluteString == "https://api.openai.com/v1/responses")
        #expect(r.headers["Authorization"] == "Bearer test-key")
        let body = try #require(try JSONSerialization.jsonObject(with: r.body ?? Data()) as? [String: Any])
        #expect(body["model"] as? String == "gpt-5-mini")
        #expect(body["temperature"] == nil)
        #expect(body["store"] as? Bool == false)
        #expect(body["instructions"] as? String == AssistantPrompt.instructions)
        let format = try #require((body["text"] as? [String: Any])?["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect(format["strict"] as? Bool == true)
        let schema = try #require(format["schema"] as? [String: Any])
        #expect((schema["required"] as? [String])?.count == AssistantPrompt.fields.count)
        // Text only: the input is a string (no image part), masked digits as given.
        let text = try #require(body["input"] as? String)
        #expect(text.contains("••••1234"))
    }

    @Test func refusalsAndErrors() async {
        await #expect(throws: AIEndpointError.badAnswer) {
            try await OpenAIAssistant(apiKey: "k", transport: FakeResponsesAPI(body: FakeResponsesAPI.answer("", refusal: true))).extract(input)
        }
        await #expect(throws: AIEndpointError.badAnswer) {
            try await OpenAIAssistant(apiKey: "k", transport: FakeResponsesAPI(body: FakeResponsesAPI.answer(json, status: "incomplete"))).extract(input)
        }
        await #expect(throws: AIEndpointError.unauthorized) {
            try await OpenAIAssistant(apiKey: "bad", transport: FakeResponsesAPI(status: 401, body: #"{"error":{}}"#)).extract(input)
        }
        await #expect(throws: AIEndpointError.http(429)) {
            try await OpenAIAssistant(apiKey: "k", transport: FakeResponsesAPI(status: 429, body: #"{"error":{}}"#)).extract(input)
        }
        await #expect(throws: AIEndpointError.http(503)) {
            try await OpenAIAssistant(apiKey: "k", transport: FakeResponsesAPI(status: 503, body: #"{"error":{}}"#)).extract(input)
        }
        let api = FakeResponsesAPI(body: "{}")
        await #expect(throws: AIEndpointError.missingKey) { try await OpenAIAssistant(apiKey: "", transport: api).extract(input) }
        #expect(api.requests.isEmpty)
    }

    @Test func userChosenModel() async throws {
        let api = FakeResponsesAPI(body: FakeResponsesAPI.answer(json))
        _ = try await OpenAIAssistant(model: "gpt-5", apiKey: "k", transport: api).extract(input)
        let body = try #require(try JSONSerialization.jsonObject(with: api.requests.last?.body ?? Data()) as? [String: Any])
        #expect(body["model"] as? String == "gpt-5")
    }
}
