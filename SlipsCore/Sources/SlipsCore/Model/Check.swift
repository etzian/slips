import Foundation

public enum CheckSeverity: String, Codable, Sendable, Comparable {
    case info, warning, blocking

    private var rank: Int {
        switch self {
        case .info: 0
        case .warning: 1
        case .blocking: 2
        }
    }

    public static func < (a: CheckSeverity, b: CheckSeverity) -> Bool { a.rank < b.rank }
}

/// One finding about a slip. `code` names a catalog key in the app (`check.<code>`); `values` fill its
/// placeholders. Stored as a JSON array in `slips.checks`.
public struct Check: Codable, Hashable, Sendable {
    public var code: String
    public var severity: CheckSeverity
    public var values: [String]

    public init(code: String, severity: CheckSeverity, values: [String] = []) {
        self.code = code
        self.severity = severity
        self.values = values
    }

    /// The PDF of the slip is not on disk (set by the startup sweep).
    public static let fileMissing = Check(code: "file_missing", severity: .blocking)
}

extension Slip {
    public var decodedChecks: [Check] {
        guard let json = checks, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([Check].self, from: data)) ?? []
    }

    public mutating func setChecks(_ list: [Check]) {
        let data = (try? JSONEncoder.sorted.encode(list)) ?? Data("[]".utf8)
        checks = String(decoding: data, as: UTF8.self)
    }
}

extension JSONEncoder {
    /// Stable output (sorted keys), so equal values give equal JSON.
    static var sorted: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }
}
