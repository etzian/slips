import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPRequest: Sendable, Hashable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?
    public var timeout: TimeInterval

    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil, timeout: TimeInterval = 30) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

public struct HTTPResponse: Sendable, Hashable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data = Data()) {
        self.status = status
        self.body = body
    }
}

/// The HTTP the WebDAV client needs. `URLSessionTransport` in the app (uploads through a background
/// session), an in-memory server in tests.
public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
    /// PUT the file at `file` (streamed from disk, never loaded whole).
    func upload(_ request: HTTPRequest, fromFile file: URL) async throws -> HTTPResponse
}

/// A WebDAV server on the LAN or the internet: a NAS, Nextcloud, a WebDAV container.
public struct WebDAVConfig: Sendable, Hashable {
    public static let baseURLKey = "base_url"
    public static let usernameKey = "username"
    public static let healthURLKey = "health_url"
    /// `"1"` when the user marked the host as on the local network: plain HTTP is then allowed.
    public static let localNetworkKey = "local_network"

    public var baseURL: URL
    public var username: String
    public var password: String
    public var healthURL: URL?
    public var localNetwork: Bool

    public init(baseURL: URL, username: String, password: String, healthURL: URL? = nil, localNetwork: Bool = false) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
        self.healthURL = healthURL
        self.localNetwork = localNetwork
    }

    /// Reads a destination's config; the password comes from the Keychain.
    public init?(destination: Destination, password: String) {
        guard let base = destination.config[Self.baseURLKey].flatMap(URL.init(string:)) else { return nil }
        self.init(baseURL: base, username: destination.config[Self.usernameKey] ?? "", password: password,
                  healthURL: destination.config[Self.healthURLKey].flatMap(URL.init(string:)),
                  localNetwork: destination.config[Self.localNetworkKey] == "1")
    }

    public var config: [String: String] {
        var c = [Self.baseURLKey: baseURL.absoluteString, Self.usernameKey: username]
        if let healthURL { c[Self.healthURLKey] = healthURL.absoluteString }
        if localNetwork { c[Self.localNetworkKey] = "1" }
        return c
    }

    public enum Problem: Error, Equatable, Sendable {
        case notAURL
        /// Plain HTTP for a host not marked local.
        case insecure
    }

    /// HTTPS is required unless the user marked the host as local.
    public static func validate(base: String, localNetwork: Bool) -> Result<URL, Problem> {
        guard let url = URL(string: base.trimmingCharacters(in: .whitespaces)), let scheme = url.scheme?.lowercased(),
              url.host?.isEmpty == false, scheme == "https" || scheme == "http"
        else { return .failure(.notAURL) }
        if scheme == "http" && !localNetwork { return .failure(.insecure) }
        return .success(url)
    }
}

/// WebDAV delivery (plan P10): probe = health URL or `OPTIONS` with a 3 s timeout; exists = `PROPFIND`
/// depth 0 with a size check; deliver = `MKCOL` for missing folders, then `PUT` from the file.
public struct WebDAVClient: DestinationAdapter {
    public static let probeTimeout: TimeInterval = 3
    let config: WebDAVConfig
    let transport: any HTTPTransport
    let localize: @Sendable (String) -> String

    public init(config: WebDAVConfig, transport: any HTTPTransport, localize: @escaping @Sendable (String) -> String = { $0 }) {
        self.config = config
        self.transport = transport
        self.localize = localize
    }

    public func probe() async -> Reachability {
        guard secure else { return .unreachable }
        let request = HTTPRequest(method: config.healthURL == nil ? "OPTIONS" : "GET", url: config.healthURL ?? config.baseURL,
                                  headers: authHeaders, timeout: Self.probeTimeout)
        guard let response = try? await transport.send(request) else { return .unreachable }
        switch response.status {
        case 200..<400: return .reachable
        case 401: return .needsAuth
        default: return .unreachable
        }
    }

    public func exists(_ item: DeliveryItem) async throws -> RemoteRef? {
        try requireSecure()
        for path in candidates(item) where try await remote(path, matches: item) == true {
            if item.destination.keepsSidecar {
                let sidecar = try await send("GET", NamingRule.sidecarPath(for: path))
                guard sidecar.status == 200, sidecar.body == (try Sidecar(slip: item.slip, labels: item.labels).encoded()) else { return nil }
            }
            return RemoteRef(path)
        }
        return nil
    }

    public func deliver(_ item: DeliveryItem) async throws -> RemoteRef {
        try requireSecure()
        let all = candidates(item)
        var chosen: String?
        var alreadyThere = false
        for path in all {
            let match = try await remote(path, matches: item)
            if match != false {
                chosen = path
                alreadyThere = match == true
                break
            }
        }
        let path = chosen ?? all[all.count - 1]
        try await makeFolders(for: path)
        if !alreadyThere {
            let request = HTTPRequest(method: "PUT", url: url(path),
                                      headers: authHeaders.merging(["Content-Type": "application/pdf"]) { a, _ in a }, timeout: 120)
            let response: HTTPResponse
            do {
                response = try await transport.upload(request, fromFile: item.pdfURL)
            } catch {
                throw DeliveryError.transient("network")
            }
            try check(response, accepting: [200, 201, 204])
        }
        if item.destination.keepsSidecar {
            let body = try Sidecar(slip: item.slip, labels: item.labels).encoded()
            try check(try await send("PUT", NamingRule.sidecarPath(for: path), body: body, contentType: "application/json"),
                      accepting: [200, 201, 204])
        }
        if let previous = item.previousRef?.value, previous != path, try await remote(previous, matches: item) == true {
            _ = try? await send("DELETE", previous)
            _ = try? await send("DELETE", NamingRule.sidecarPath(for: previous))
        }
        return RemoteRef(path)
    }

    // MARK: - Requests

    var secure: Bool {
        config.baseURL.scheme?.lowercased() == "https" || config.localNetwork
    }

    func requireSecure() throws {
        guard secure else { throw DeliveryError.permanent("insecure_http") }
    }

    var authHeaders: [String: String] {
        guard !config.username.isEmpty else { return [:] }
        let token = Data("\(config.username):\(config.password)".utf8).base64EncodedString()
        return ["Authorization": "Basic \(token)"]
    }

    func candidates(_ item: DeliveryItem) -> [String] {
        let path = NamingRule(item.destination.namingRule).path(for: item.slip, labels: item.labels, localize: localize)
        return [path, NamingRule.withIdSuffix(path, slip: item.slip)]
    }

    /// The URL of a relative path under the base, each part percent-encoded.
    func url(_ path: String, directory: Bool = false) -> URL {
        var base = config.baseURL.absoluteString
        if !base.hasSuffix("/") { base += "/" }
        let encoded = path.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#[]@!$&'()*+,;=")))
                ?? String($0)
        }.joined(separator: "/")
        return URL(string: base + encoded + (directory ? "/" : ""))!
    }

    func send(_ method: String, _ path: String, directory: Bool = false, body: Data? = nil, contentType: String? = nil,
              headers extra: [String: String] = [:]) async throws -> HTTPResponse {
        var headers = authHeaders.merging(extra) { _, new in new }
        if let contentType { headers["Content-Type"] = contentType }
        do {
            let response = try await transport.send(HTTPRequest(method: method, url: url(path, directory: directory), headers: headers, body: body))
            if response.status == 401 { throw DeliveryError.unauthorized }
            return response
        } catch let error as DeliveryError {
            throw error
        } catch {
            throw DeliveryError.transient("network")
        }
    }

    /// Whether the file at `path` is this slip's PDF: nil when there is no file, then size, then the
    /// SHA-256 of its content (a different slip can have the same name and size).
    func remote(_ path: String, matches item: DeliveryItem) async throws -> Bool? {
        guard let size = try await remoteSize(path) else { return nil }
        guard size == item.byteCount else { return false }
        let response = try await send("GET", path)
        guard response.status == 200 else { return false }
        return Hashing.sha256Hex(response.body) == item.sha256
    }

    /// The size of the file at `path`, nil when there is none.
    func remoteSize(_ path: String) async throws -> Int? {
        let body = Data("""
            <?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:"><d:prop><d:getcontentlength/><d:resourcetype/></d:prop></d:propfind>
            """.utf8)
        let response = try await send("PROPFIND", path, body: body, contentType: "application/xml", headers: ["Depth": "0"])
        switch response.status {
        case 404: return nil
        case 207, 200:
            return PropfindParser.contentLength(response.body) ?? -1
        default:
            try check(response, accepting: [207])
            return nil
        }
    }

    /// `MKCOL` for each folder of `path`; 405 means it exists already.
    func makeFolders(for path: String) async throws {
        var parts = path.split(separator: "/").map(String.init)
        parts.removeLast()
        var current = ""
        for part in parts {
            current += (current.isEmpty ? "" : "/") + part
            let response = try await send("MKCOL", current, directory: true)
            switch response.status {
            case 201, 405, 301: continue
            case 409: throw DeliveryError.permanent("base_missing")
            default: try check(response, accepting: [201, 405])
            }
        }
    }

    func check(_ response: HTTPResponse, accepting ok: Set<Int>) throws {
        if ok.contains(response.status) { return }
        switch response.status {
        case 401: throw DeliveryError.unauthorized
        case 403, 404, 405, 409, 413, 415: throw DeliveryError.permanent("http_\(response.status)")
        default: throw DeliveryError.transient("http_\(response.status)")
        }
    }
}

/// Reads `getcontentlength` out of a PROPFIND multistatus body, namespace prefix or not.
enum PropfindParser {
    static func contentLength(_ body: Data) -> Int? {
        let text = String(decoding: body, as: UTF8.self)
        guard let g = text.regexFirstMatch(#"<(?:[A-Za-z0-9]+:)?getcontentlength[^>]*>\s*(\d+)\s*<"#) else { return nil }
        return Int(g[1])
    }
}

/// `URLSession` for the requests that are not uploads (and uploads when no background session is
/// given), in the core so it works the same everywhere.
public struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: urlRequest(request))
        return HTTPResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
    }

    public func upload(_ request: HTTPRequest, fromFile file: URL) async throws -> HTTPResponse {
        let (data, response) = try await session.upload(for: urlRequest(request), fromFile: file)
        return HTTPResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
    }

    public func urlRequest(_ r: HTTPRequest) -> URLRequest {
        var request = URLRequest(url: r.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: r.timeout)
        request.httpMethod = r.method
        request.httpBody = r.body
        for (k, v) in r.headers { request.setValue(v, forHTTPHeaderField: k) }
        return request
    }
}
