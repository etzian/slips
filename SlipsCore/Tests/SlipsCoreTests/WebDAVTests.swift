import Foundation
import Testing
@testable import SlipsCore

/// An in-process WebDAV server: files and folders in memory, Basic auth, scripted failures.
final class FakeWebDAVServer: HTTPTransport, @unchecked Sendable {
    // @unchecked: every mutable field is guarded by `lock`.
    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private var folders: Set<String> = ["/dav"]
    private var failures: [Int] = []
    private var _requests: [String] = []
    private var _puts = 0
    var user = "tester"
    var password = "fake-password"
    /// Every request answers this status while set (a server down for ten minutes).
    var outage: Int? {
        get { lock.withLock { _outage } }
        set { lock.withLock { _outage = newValue } }
    }
    private var _outage: Int?
    /// The next PUT stores the file but the connection drops before the answer.
    var dropNextPutAnswer = false

    var requests: [String] { lock.withLock { _requests } }
    var puts: Int { lock.withLock { _puts } }
    func file(_ path: String) -> Data? { lock.withLock { files[path] } }
    func fileNames() -> [String] { lock.withLock { files.keys.sorted() } }
    func failNext(_ statuses: Int...) { lock.withLock { failures.append(contentsOf: statuses) } }
    func put(_ path: String, _ data: Data) { lock.withLock { files[path] = data } }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try handle(request, body: request.body)
    }

    func upload(_ request: HTTPRequest, fromFile file: URL) async throws -> HTTPResponse {
        try handle(request, body: try Data(contentsOf: file))
    }

    private func handle(_ r: HTTPRequest, body: Data?) throws -> HTTPResponse {
        try lock.withLock {
            let path = r.url.path.removingPercentEncoding.map { $0.hasSuffix("/") && $0.count > 1 ? String($0.dropLast()) : $0 } ?? r.url.path
            _requests.append("\(r.method) \(path)")
            if let outage = _outage { return HTTPResponse(status: outage) }
            if !failures.isEmpty { return HTTPResponse(status: failures.removeFirst()) }
            let expected = "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
            guard r.headers["Authorization"] == expected else { return HTTPResponse(status: 401) }
            let parent = (path as NSString).deletingLastPathComponent
            switch r.method {
            case "OPTIONS", "GET" where r.url.path.hasSuffix("/health"):
                return HTTPResponse(status: 200)
            case "GET":
                return files[path].map { HTTPResponse(status: 200, body: $0) } ?? HTTPResponse(status: 404)
            case "PROPFIND":
                if let data = files[path] {
                    return HTTPResponse(status: 207, body: Data("""
                        <?xml version="1.0"?><D:multistatus xmlns:D="DAV:"><D:response><D:href>\(path)</D:href><D:propstat><D:prop>
                        <D:getcontentlength>\(data.count)</D:getcontentlength><D:resourcetype/></D:prop></D:propstat></D:response></D:multistatus>
                        """.utf8))
                }
                return folders.contains(path) ? HTTPResponse(status: 207, body: Data("<D:multistatus xmlns:D=\"DAV:\"/>".utf8))
                    : HTTPResponse(status: 404)
            case "MKCOL":
                if folders.contains(path) || files[path] != nil { return HTTPResponse(status: 405) }
                guard folders.contains(parent) else { return HTTPResponse(status: 409) }
                folders.insert(path)
                return HTTPResponse(status: 201)
            case "PUT":
                guard folders.contains(parent) else { return HTTPResponse(status: 409) }
                files[path] = body ?? Data()
                _puts += 1
                if dropNextPutAnswer && path.hasSuffix(".pdf") {
                    dropNextPutAnswer = false
                    throw URLError(.timedOut)
                }
                return HTTPResponse(status: 201)
            case "DELETE":
                return files.removeValue(forKey: path) == nil ? HTTPResponse(status: 404) : HTTPResponse(status: 204)
            default:
                return HTTPResponse(status: 405)
            }
        }
    }
}

@Suite struct WebDAVTests {
    let server = FakeWebDAVServer()
    let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    func client(base: String = "https://nas.example.test/dav", password: String = "fake-password", health: String? = nil,
                local: Bool = false) -> WebDAVClient {
        WebDAVClient(config: WebDAVConfig(baseURL: URL(string: base)!, username: "tester", password: password,
                                          healthURL: health.flatMap(URL.init(string:)), localNetwork: local),
                     transport: server)
    }

    func item(merchant: String = "Fake", content: String = "%PDF webdav", sidecar: Bool = false, previous: String? = nil,
              id: UUID = UUID()) throws -> DeliveryItem {
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let data = Data(content.utf8)
        let url = source.appendingPathComponent("\(UUID()).pdf")
        try data.write(to: url)
        var s = Slip(id: id, profileId: UUID(), status: .ready, pdfPath: "x", pdfSha256: Hashing.sha256Hex(data), pageCount: 1)
        s.merchant = merchant
        s.txnDate = CalendarDay(year: 2026, month: 10, day: 20)
        s.total = 1000
        let d = Destination(profileId: s.profileId, type: .webdav, name: "NAS", config: sidecar ? [Destination.sidecarKey: "1"] : [:],
                            enabled: true)
        return DeliveryItem(slip: s, destination: d, pdfURL: url, sha256: s.pdfSha256, byteCount: data.count,
                            previousRef: previous.map(RemoteRef.init), labels: SlipLabels(business: "Shop Fictif"))
    }

    @Test func probe() async {
        #expect(await client().probe() == .reachable)
        #expect(server.requests.last == "OPTIONS /dav")
        #expect(await client(health: "https://nas.example.test/health").probe() == .reachable)
        #expect(server.requests.last == "GET /health")
        #expect(await client(password: "wrong").probe() == .needsAuth)
        server.outage = 503
        #expect(await client().probe() == .unreachable)
    }

    @Test func deliverMakesFoldersThenPuts() async throws {
        let c = client()
        let i = try item()
        #expect(try await c.exists(i) == nil)
        let ref = try await c.deliver(i)
        #expect(ref.value == "Shop Fictif/2026/2026-10-20_Fake_10.00.pdf")
        #expect(server.file("/dav/Shop Fictif/2026/2026-10-20_Fake_10.00.pdf") == Data("%PDF webdav".utf8))
        #expect(server.requests.contains("MKCOL /dav/Shop Fictif"))
        #expect(server.requests.contains("MKCOL /dav/Shop Fictif/2026"))
        #expect(try await c.exists(i) == ref)
        // Again: nothing uploaded twice.
        _ = try await c.deliver(i)
        #expect(server.puts == 1)
    }

    @Test func plainHTTPRefusedUnlessLocal() async throws {
        #expect(await client(base: "http://nas.example.test/dav").probe() == .unreachable)
        await #expect(throws: DeliveryError.permanent("insecure_http")) {
            try await client(base: "http://nas.example.test/dav").deliver(try item())
        }
        #expect(await client(base: "http://192.168.1.20/dav", local: true).probe() == .reachable)
        #expect(WebDAVConfig.validate(base: "http://nas.local/dav", localNetwork: false) == .failure(.insecure))
        #expect(WebDAVConfig.validate(base: "http://nas.local/dav", localNetwork: true) == .success(URL(string: "http://nas.local/dav")!))
        #expect(WebDAVConfig.validate(base: "nas", localNetwork: true) == .failure(.notAURL))
        #expect(WebDAVConfig.validate(base: "ftp://nas/dav", localNetwork: true) == .failure(.notAURL))
    }

    @Test func errorsMapToOutboxOutcomes() async throws {
        let c = client()
        server.failNext(401)
        await #expect(throws: DeliveryError.unauthorized) { try await c.deliver(try item()) }
        server.failNext(500)
        await #expect(throws: DeliveryError.transient("http_500")) { try await c.deliver(try item()) }
        server.failNext(404, 403)
        await #expect(throws: DeliveryError.permanent("http_403")) { try await c.deliver(try item()) }
        await #expect(throws: DeliveryError.permanent("base_missing")) {
            try await client(base: "https://nas.example.test/missing").deliver(try item())
        }
    }

    @Test func nameTakenGetsTheId() async throws {
        let c = client()
        let a = try await c.deliver(try item(content: "%PDF first"))
        let second = try item(content: "%PDF second, longer")
        let b = try await c.deliver(second)
        #expect(a != b)
        #expect(b.value.hasSuffix("_\(second.slip.id.uuidString.lowercased().prefix(8)).pdf"))
    }

    @Test func sidecarAndRename() async throws {
        let c = client()
        let id = UUID()
        let before = try item(merchant: "Old", sidecar: true, id: id)
        let old = try await c.deliver(before)
        #expect(server.file("/dav/" + NamingRule.sidecarPath(for: old.value)) != nil)
        let after = try item(merchant: "New", sidecar: true, previous: old.value, id: id)
        #expect(try await c.exists(after) == nil)
        let new = try await c.deliver(after)
        #expect(server.file("/dav/" + old.value) == nil)
        #expect(server.file("/dav/" + NamingRule.sidecarPath(for: old.value)) == nil)
        #expect(server.file("/dav/" + new.value) != nil)
        #expect(try await c.exists(after) == new)
    }

    @Test func percentEncodedPaths() {
        let u = client().url("Café Fictif/2026/a#b?.pdf")
        #expect(u.absoluteString == "https://nas.example.test/dav/Caf%C3%A9%20Fictif/2026/a%23b%3F.pdf")
    }

    @Test func propfindParsing() {
        #expect(PropfindParser.contentLength(Data("<d:getcontentlength>1234</d:getcontentlength>".utf8)) == 1234)
        #expect(PropfindParser.contentLength(Data("<getcontentlength xmlns=\"DAV:\"> 7 </getcontentlength>".utf8)) == 7)
        #expect(PropfindParser.contentLength(Data("<d:multistatus/>".utf8)) == nil)
    }
}

/// The plan's exit scenarios, through the outbox.
@Suite struct WebDAVOutboxTests {
    @Test func serverDownTenMinutesThenUpDeliversOnceWithoutHoldingOthers() async throws {
        let h = try OutboxHarness()
        let server = FakeWebDAVServer()
        let nas = try h.destination("NAS")
        let other = try h.destination("Other")
        let otherFake = FakeDestination(name: "other")
        let slips = try (0..<3).map { _ in try h.readySlip([nas, other]) }
        let client = WebDAVClient(config: WebDAVConfig(baseURL: URL(string: "https://nas.example.test/dav")!, username: "tester",
                                                       password: "fake-password"), transport: server)
        let outbox = Outbox(database: h.db, files: h.files,
                            adapters: { $0.id == nas.id ? client : $0.id == other.id ? otherFake : nil },
                            now: { h.clock.now })
        server.outage = 500
        // Ten minutes of 500s: the probe fails, the other destination is not held up.
        var elapsed: TimeInterval = 0
        while elapsed < 600 {
            await outbox.drain()
            h.clock.advance(30)
            elapsed += 30
        }
        for s in slips { #expect(try h.delivery(s, other).status == .done) }
        for s in slips { #expect(try h.delivery(s, nas).status == .pending) }
        server.outage = nil
        h.clock.advance(3600)
        let report = await outbox.drain()
        #expect(report.delivered == 3)
        #expect(server.puts == 3)
        #expect(server.fileNames().count == 3)
        for s in slips { #expect(try h.delivery(s, nas).status == .done) }
    }

    @Test func lostAnswerAfterPutIsNotDuplicated() async throws {
        let h = try OutboxHarness()
        let server = FakeWebDAVServer()
        server.dropNextPutAnswer = true
        let nas = try h.destination("NAS")
        let slip = try h.readySlip([nas])
        let client = WebDAVClient(config: WebDAVConfig(baseURL: URL(string: "https://nas.example.test/dav")!, username: "tester",
                                                       password: "fake-password"), transport: server)
        let outbox = Outbox(database: h.db, files: h.files, adapters: { _ in client }, now: { h.clock.now })
        #expect(await outbox.drain().retryLater == 1)
        h.clock.advance(30)
        #expect(await outbox.drain().alreadyThere == 1)
        #expect(server.puts == 1)
        #expect(try h.delivery(slip, nas).status == .done)
    }
}
