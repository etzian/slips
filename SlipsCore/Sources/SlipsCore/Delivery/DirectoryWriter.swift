import Foundation

/// Delivers slips into a folder: the iCloud container, a folder picked in Files, an SMB share mounted
/// in Files. The file name follows the destination's naming rule; a name taken by another file gets
/// `_{id8}`; the sidecar sits next to the PDF when the destination keeps one. A slip re-delivered after
/// an edit replaces its earlier copy, which is removed only if it is still byte-identical.
public struct DirectoryWriter: Sendable {
    public let root: URL
    let localize: @Sendable (String) -> String

    public init(root: URL, localize: @escaping @Sendable (String) -> String = { $0 }) {
        self.root = root
        self.localize = localize
    }

    public func exists(_ item: DeliveryItem) throws -> RemoteRef? {
        for path in candidates(item) where holdsSlip(path, item) {
            if item.destination.keepsSidecar {
                let sidecar = url(NamingRule.sidecarPath(for: path))
                let expected = try sidecarData(item)
                let actual = try? Data(contentsOf: sidecar)
                guard actual == expected else { return nil }
            }
            return RemoteRef(path)
        }
        return nil
    }

    public func deliver(_ item: DeliveryItem) throws -> RemoteRef {
        let fm = FileManager.default
        let path = candidates(item).first { path in
            !fm.fileExists(atPath: url(path).path) || holdsSlip(path, item)
        } ?? NamingRule.withIdSuffix(candidates(item)[0], slip: item.slip)
        let target = url(path)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !holdsSlip(path, item) {
            try replace(target, with: Data(contentsOf: item.pdfURL))
        }
        if item.destination.keepsSidecar {
            try replace(url(NamingRule.sidecarPath(for: path)), with: sidecarData(item))
        }
        if let previous = item.previousRef?.value, previous != path {
            try removeIfOurs(previous, item)
        }
        return RemoteRef(path)
    }

    /// The rule's path, then the same with the slip's id when another file holds the name.
    func candidates(_ item: DeliveryItem) -> [String] {
        let path = NamingRule(item.destination.namingRule).path(for: item.slip, labels: item.labels, localize: localize)
        return [path, NamingRule.withIdSuffix(path, slip: item.slip)]
    }

    func url(_ path: String) -> URL {
        root.appendingPathComponent(path, isDirectory: false)
    }

    /// The file at `path` is this slip's PDF: same size, same hash.
    func holdsSlip(_ path: String, _ item: DeliveryItem) -> Bool {
        let u = url(path)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: u.path),
              (attrs[.size] as? NSNumber)?.intValue == item.byteCount,
              let data = try? Data(contentsOf: u)
        else { return false }
        return Hashing.sha256Hex(data) == item.sha256
    }

    func sidecarData(_ item: DeliveryItem) throws -> Data {
        try Sidecar(slip: item.slip, labels: item.labels).encoded()
    }

    /// Writes beside the target, then renames it over (`.atomic`), so a reader never sees half a file.
    func replace(_ target: URL, with data: Data) throws {
        try data.write(to: target, options: .atomic)
    }

    func removeIfOurs(_ path: String, _ item: DeliveryItem) throws {
        guard holdsSlip(path, item) else { return }
        try? FileManager.default.removeItem(at: url(path))
        let sidecar = url(NamingRule.sidecarPath(for: path))
        if let data = try? Data(contentsOf: sidecar),
           let old = try? JSONDecoder.sidecar.decode(Sidecar.self, from: data), old.id == item.slip.id.uuidString.lowercased() {
            try? FileManager.default.removeItem(at: sidecar)
        }
    }
}

extension JSONDecoder {
    static var sidecar: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
