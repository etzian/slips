import Foundation

/// Data protection class of a file (plan §9). No effect off iOS.
public enum FileProtection: Sendable {
    /// Slip PDFs: readable only while the device is unlocked.
    case complete
    /// Files the outbox reads in the background: readable after the first unlock since boot.
    case untilFirstUnlock
}

/// Slip files on disk under `<root>/Slips/<profile-id>/<slip-id>/`. Paths stored in the database are
/// relative to `root`, so moving the container does not break them. Writes are atomic.
public struct FileStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static let pdfName = "slip.pdf"

    /// `Slips/<profile>/<slip>`, relative to `root`.
    public static func slipDirectory(profile: UUID, slip: UUID) -> String {
        "Slips/\(profile.uuidString.lowercased())/\(slip.uuidString.lowercased())"
    }

    /// `Slips/<profile>/<slip>/slip.pdf`, relative to `root`.
    public static func pdfPath(profile: UUID, slip: UUID) -> String {
        slipDirectory(profile: profile, slip: slip) + "/" + pdfName
    }

    public func url(for relativePath: String) -> URL {
        root.appendingPathComponent(relativePath, isDirectory: false)
    }

    /// Writes `data` atomically at `relativePath`, creating folders, with the given protection class.
    public func write(_ data: Data, to relativePath: String, protection: FileProtection = .complete) throws {
        let target = url(for: relativePath)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: Self.options(for: protection))
    }

    /// Writes a slip's PDF and returns its relative path.
    @discardableResult
    public func writePDF(_ data: Data, profile: UUID, slip: UUID) throws -> String {
        let path = Self.pdfPath(profile: profile, slip: slip)
        try write(data, to: path, protection: .complete)
        return path
    }

    public func read(_ relativePath: String) throws -> Data {
        try Data(contentsOf: url(for: relativePath))
    }

    public func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: relativePath).path)
    }

    /// Removes a slip's folder and everything in it. Missing is not an error.
    public func removeSlip(profile: UUID, slip: UUID) throws {
        let dir = url(for: Self.slipDirectory(profile: profile, slip: slip))
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    /// Every `(profile, slip)` folder on disk, for the startup sweep.
    public func slipFolders() throws -> [(profile: UUID, slip: UUID)] {
        let base = url(for: "Slips")
        let fm = FileManager.default
        guard fm.fileExists(atPath: base.path) else { return [] }
        var result: [(UUID, UUID)] = []
        for p in try fm.contentsOfDirectory(atPath: base.path) {
            guard let profile = UUID(uuidString: p) else { continue }
            for s in try fm.contentsOfDirectory(atPath: base.appendingPathComponent(p).path) {
                if let slip = UUID(uuidString: s) { result.append((profile, slip)) }
            }
        }
        return result
    }

    static func options(for protection: FileProtection) -> Data.WritingOptions {
        #if os(iOS)
        switch protection {
        case .complete: [.atomic, .completeFileProtection]
        case .untilFirstUnlock: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        }
        #else
        [.atomic]
        #endif
    }
}
