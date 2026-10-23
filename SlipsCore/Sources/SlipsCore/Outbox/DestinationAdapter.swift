import Foundation

/// Whether a destination can take a delivery right now.
public enum Reachability: Sendable, Equatable {
    case reachable
    case unreachable
    /// The destination refuses our credentials (401, expired token, stale bookmark).
    case needsAuth
}

/// Where a delivered slip landed at a destination: a path, a URL or a remote id.
public struct RemoteRef: Sendable, Hashable, Codable {
    public var value: String

    public init(_ value: String) {
        self.value = value
    }
}

/// Everything an adapter needs to deliver one slip.
public struct DeliveryItem: Sendable {
    public var slip: Slip
    public var destination: Destination
    /// The PDF on disk; adapters read it, never copy it into memory twice.
    public var pdfURL: URL
    public var sha256: String
    public var byteCount: Int
    /// Where an earlier delivery of this slip landed, when it is re-delivered after an edit.
    public var previousRef: RemoteRef?
    /// Names of the slip's business, sub-category and payment method, for naming rules and sidecars.
    public var labels: SlipLabels

    public init(slip: Slip, destination: Destination, pdfURL: URL, sha256: String, byteCount: Int, previousRef: RemoteRef?,
                labels: SlipLabels = SlipLabels()) {
        self.labels = labels
        self.slip = slip
        self.destination = destination
        self.pdfURL = pdfURL
        self.sha256 = sha256
        self.byteCount = byteCount
        self.previousRef = previousRef
    }
}

/// How a delivery attempt failed.
public enum DeliveryError: Error, Sendable, Equatable {
    /// 401 or a refresh failure: stop retrying this destination until the user signs in again.
    case unauthorized
    /// Worth retrying later (offline, timeout, 5xx). `code` is stored in `last_error_code`.
    case transient(String)
    /// Retrying will not help (403, 404 on the base folder, quota): `failed` at once.
    case permanent(String)
}

/// One kind of destination (iCloud, a Files folder, WebDAV, fin…). Concrete adapters that need iOS
/// APIs live in the app target; the outbox and its tests only see this protocol (plan §2).
public protocol DestinationAdapter: Sendable {
    func probe() async -> Reachability
    /// The remote copy of `item` if one with the same content is already there, so a retry after a
    /// write whose answer was lost never creates a second copy.
    func exists(_ item: DeliveryItem) async throws -> RemoteRef?
    func deliver(_ item: DeliveryItem) async throws -> RemoteRef
}

/// The network as the outbox sees it, for `wifi_only` and Low Data Mode.
public struct NetworkConditions: Sendable, Equatable {
    public var isWiFi: Bool
    /// Low Data Mode or a constrained path.
    public var isConstrained: Bool

    public init(isWiFi: Bool, isConstrained: Bool) {
        self.isWiFi = isWiFi
        self.isConstrained = isConstrained
    }

    public static let unrestricted = NetworkConditions(isWiFi: true, isConstrained: false)

    /// A Wi-Fi-only destination waits for an unconstrained Wi-Fi path.
    public func allows(_ destination: Destination) -> Bool {
        !destination.wifiOnly || (isWiFi && !isConstrained)
    }
}
