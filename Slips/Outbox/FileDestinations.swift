import Foundation
import SlipsCore

/// Catalog lookups for naming rules and sidecars (kind and sub-category names), safe off the main thread.
let catalogLocalize: @Sendable (String) -> String = { Bundle.main.localizedString(forKey: $0, value: $0, table: nil) }

/// iCloud Drive: the app's ubiquity container, `Documents/` so the slips show in Files. Done once the
/// file is written locally; iOS syncs it. Without iCloud (signed out, or no container entitlement)
/// the rows wait.
struct ICloudAdapter: DestinationAdapter {
    static let containerId = "iCloud.com.etzian.slips"

    func probe() async -> Reachability {
        Self.documents() == nil ? .unreachable : .reachable
    }

    func exists(_ item: DeliveryItem) async throws -> RemoteRef? {
        guard let root = Self.documents() else { throw DeliveryError.transient("icloud_unavailable") }
        return try Coordinated.write(root) { try DirectoryWriter(root: $0, localize: catalogLocalize).exists(item) }
    }

    func deliver(_ item: DeliveryItem) async throws -> RemoteRef {
        guard let root = Self.documents() else { throw DeliveryError.transient("icloud_unavailable") }
        return try Coordinated.write(root) { try DirectoryWriter(root: $0, localize: catalogLocalize).deliver(item) }
    }

    /// May block: never call on the main thread.
    static func documents() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: containerId)?.appendingPathComponent("Documents", isDirectory: true)
    }
}

/// A folder the user picked in Files (iCloud Drive, On My iPhone, an SMB share, a File Provider app),
/// kept as a security-scoped bookmark in the destination's config. A stale or refused bookmark asks
/// the user to pick the folder again.
struct FolderAdapter: DestinationAdapter {
    static let bookmarkKey = "bookmark"
    let destination: Destination

    func probe() async -> Reachability {
        switch resolve() {
        case .success: .reachable
        case .failure(let e): e == .unauthorized ? .needsAuth : .unreachable
        }
    }

    func exists(_ item: DeliveryItem) async throws -> RemoteRef? {
        try withFolder { try DirectoryWriter(root: $0, localize: catalogLocalize).exists(item) }
    }

    func deliver(_ item: DeliveryItem) async throws -> RemoteRef {
        try withFolder { try DirectoryWriter(root: $0, localize: catalogLocalize).deliver(item) }
    }

    private func withFolder<T>(_ body: (URL) throws -> T) throws -> T {
        let url = try resolve().get()
        guard url.startAccessingSecurityScopedResource() else { throw DeliveryError.unauthorized }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            return try Coordinated.write(url, body)
        } catch let error as DeliveryError {
            throw error
        } catch let error as CocoaError where error.code == .fileWriteNoPermission || error.code == .fileReadNoPermission {
            throw DeliveryError.unauthorized
        } catch {
            throw DeliveryError.transient("folder_write")
        }
    }

    private func resolve() -> Result<URL, DeliveryError> {
        guard let encoded = destination.config[Self.bookmarkKey], let data = Data(base64Encoded: encoded) else {
            return .failure(.unauthorized)
        }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale), !stale else {
            return .failure(.unauthorized)
        }
        return .success(url)
    }

    /// The config entry for a folder the user just picked (inside its security scope).
    static func config(for folder: URL) throws -> [String: String] {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        let data = try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        return [bookmarkKey: data.base64EncodedString(), "folder_name": folder.lastPathComponent]
    }
}

/// Writes through `NSFileCoordinator`, so iCloud and File Provider extensions see consistent files.
enum Coordinated {
    static func write<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, any Error> = .failure(DeliveryError.transient("coordination"))
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { coordinated in
            result = Result { try body(coordinated) }
        }
        if let coordinationError { throw DeliveryError.transient("coordination_\(coordinationError.code)") }
        return try result.get()
    }
}
