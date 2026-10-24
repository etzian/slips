import Foundation
import Testing
@testable import SlipsCore

/// Answers like an Ollama server and keeps every request.
final class FakeOllama: HTTPTransport, @unchecked Sendable {
    // @unchecked: `requests` and `reply` are guarded by `lock`.
    private let lock = NSLock()
    private var _requests: [HTTPRequest] = []
    private var _reply: (Int, String)
    var requests: [HTTPRequest] { lock.withLock { _requests } }

    init(status: Int = 200, content: String) {
        let escaped = String(decoding: try! JSONEncoder().encode(content), as: UTF8.self)
        _reply = (status, #"{"model":"m","message":{"role":"assistant","content":\#(escaped)},"done":true}"#)
    }

    init(status: Int, raw: String) {
        _reply = (status, raw)
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let reply = lock.withLock { () -> (Int, String) in
            _requests.append(request)
            return _reply
        }
        if request.url.path.hasSuffix("/api/tags") { return HTTPResponse(status: 200, body: Data(#"{"models":[]}"#.utf8)) }
        return HTTPResponse(status: reply.0, body: Data(reply.1.utf8))
    }

    func upload(_ request: HTTPRequest, fromFile file: URL) async throws -> HTTPResponse {
        HTTPResponse(status: 405)
    }
}

@Suite struct OllamaTests {
    let answer = #"{"merchant":"Fake Store","date":"2026-10-20","subtotal":10.00,"gst":0.50,"qst":1.00,"hst":null,"tip":null,"total":11.50,"currency":"CAD","supplier_gst_no":null,"supplier_qst_no":null,"subcategory_key":"personal.groceries"}"#

    func assistant(_ server: FakeOllama, base: String = "http://nas.local:11434/", local: Bool = true) -> OllamaAssistant {
        OllamaAssistant(baseURL: URL(string: base)!, model: "llama3.2", localNetwork: local, transport: server)
    }

    let input = AssistantInput(ocrText: "VISA ••••1234\nTOTAL 11,50", localeIdentifier: "fr_CA", currencyHint: "CAD",
                               referenceDay: CalendarDay(year: 2026, month: 10, day: 20))

    @Test func requestShape() async throws {
        let server = FakeOllama(content: answer)
        let reading = try await assistant(server).extract(input)
        #expect(reading.total?.value == 1150)
        #expect(reading.subcategoryKey?.value == "personal.groceries")
        let request = try #require(server.requests.last)
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "http://nas.local:11434/api/chat")
        let body = try #require(try JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: Any])
        #expect(body["model"] as? String == "llama3.2")
        #expect(body["stream"] as? Bool == false)
        #expect(body["format"] is [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["system", "user"])
        #expect((messages[1]["content"] as? String)?.contains("VISA ••••1234") == true)
        // No picture is ever attached.
        #expect(messages.allSatisfy { $0["images"] == nil })
        #expect(String(decoding: request.body ?? Data(), as: UTF8.self).contains("images") == false)
    }

    @Test func plainHTTPOnlyForLocalHosts() async {
        let server = FakeOllama(content: answer)
        await #expect(throws: AIEndpointError.insecure) {
            try await assistant(server, base: "http://ollama.example.test", local: false).extract(input)
        }
        #expect(server.requests.isEmpty)
        #expect(await assistant(server, base: "http://ollama.example.test", local: false).probe() == .unreachable)
        #expect(await assistant(server).probe() == .reachable)
        let https = OllamaAssistant(baseURL: URL(string: "https://ollama.example.test")!, model: "m", localNetwork: false, transport: server)
        #expect(await https.probe() == .reachable)
    }

    @Test func errorsAndBadAnswers() async {
        await #expect(throws: AIEndpointError.http(404)) {
            try await assistant(FakeOllama(status: 404, raw: #"{"error":"model not found"}"#)).extract(input)
        }
        await #expect(throws: AIEndpointError.badAnswer) {
            try await assistant(FakeOllama(content: "Sorry, I cannot read receipts.")).extract(input)
        }
        await #expect(throws: AIEndpointError.badAnswer) {
            try await assistant(FakeOllama(status: 200, raw: "not json")).extract(input)
        }
    }

    @Test func fromSettings() {
        let server = FakeOllama(content: answer)
        var s = AIEndpointSettings(profileId: UUID(), provider: .ollama, baseUrl: "http://192.168.1.20:11434", localNetwork: true)
        #expect(OllamaAssistant(settings: s, defaultModel: "llama3.2", transport: server)?.model == "llama3.2")
        s.model = "qwen2.5"
        #expect(OllamaAssistant(settings: s, defaultModel: "llama3.2", transport: server)?.model == "qwen2.5")
        s.localNetwork = false
        #expect(OllamaAssistant(settings: s, defaultModel: "llama3.2", transport: server) == nil)
        s.baseUrl = nil
        #expect(OllamaAssistant(settings: s, defaultModel: "llama3.2", transport: server) == nil)
    }
}
