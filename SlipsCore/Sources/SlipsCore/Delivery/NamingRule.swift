import Foundation
import GRDB

/// The names a slip's file name can use, resolved from the database. Kind and seeded sub-category
/// names are translated by the caller through `localize`.
public struct SlipLabels: Sendable, Hashable, Codable {
    public var business: String?
    public var subcategoryKey: String?
    public var subcategoryName: String?
    public var paymentMethod: String?

    public init(business: String? = nil, subcategoryKey: String? = nil, subcategoryName: String? = nil, paymentMethod: String? = nil) {
        self.business = business
        self.subcategoryKey = subcategoryKey
        self.subcategoryName = subcategoryName
        self.paymentMethod = paymentMethod
    }
}

/// A destination's file naming rule (plan §6). Tokens: `{year} {month} {day} {date} {kind} {business}
/// {subcategory} {merchant} {total} {currency} {payment} {id8}`; `/` separates folders. Every value is
/// sanitised for every target: no `/ : \ * ? " < > |`, NFC, each path part at most 120 characters.
public struct NamingRule: Sendable, Hashable {
    public static let defaultRule = Destination.defaultNamingRule
    public static let maxComponentLength = 120
    public static let tokens = ["year", "month", "day", "date", "kind", "business", "subcategory", "merchant",
                                "total", "currency", "payment", "id8"]
    static let forbidden = CharacterSet(charactersIn: "/:\\*?\"<>|").union(.controlCharacters)

    public var pattern: String

    public init(_ pattern: String) {
        self.pattern = pattern
    }

    /// Tokens the rule uses that the list does not know, for the editor to refuse.
    public var unknownTokens: [String] {
        pattern.regexMatches(#"\{([^}]*)\}"#).map { $0[1] }.filter { !Self.tokens.contains($0) }
    }

    /// The relative path of `slip`, `.pdf` added when the rule has no extension. Empty folder parts
    /// (a token with no value) are dropped.
    public func path(for slip: Slip, labels: SlipLabels, localize: (String) -> String = { $0 }) -> String {
        let day = slip.txnDate ?? CalendarDay(slip.capturedAt, calendar: Self.utc)
        let id8 = String(slip.id.uuidString.lowercased().prefix(8))
        var values: [String: String] = [
            "year": String(format: "%04d", day.year),
            "month": String(format: "%02d", day.month),
            "day": String(format: "%02d", day.day),
            "date": day.iso,
            "kind": slip.kind.map { localize("kind.\($0.rawValue)") } ?? "",
            "business": labels.business ?? "",
            "subcategory": labels.subcategoryName ?? labels.subcategoryKey.map { localize("subcategory.\($0)") } ?? "",
            "merchant": slip.merchant ?? "",
            "total": slip.total.map { Self.plainAmount($0, currency: slip.currency) } ?? "",
            "currency": slip.currency,
            "payment": labels.paymentMethod ?? "",
            "id8": id8,
        ]
        for (k, v) in values { values[k] = Self.sanitize(v) }

        var parts = pattern.split(separator: "/", omittingEmptySubsequences: true).map { part -> String in
            var out = String(part)
            for (k, v) in values { out = out.replacingOccurrences(of: "{\(k)}", with: v) }
            return out
        }
        // A folder whose tokens were all empty disappears; an empty file name falls back to the id.
        let file = parts.popLast() ?? ""
        parts = parts.map(Self.cleanComponent).filter { !$0.isEmpty }
        let base = file.lowercased().hasSuffix(".pdf") ? String(file.dropLast(4)) : file
        var name = Self.cleanComponent(base)
        if name.isEmpty { name = id8 }
        parts.append(Self.cap(name + ".pdf"))
        return parts.map(Self.cap).joined(separator: "/")
    }

    /// `path` with `_{id8}` before the extension, used when another slip's file has the name.
    public static func withIdSuffix(_ path: String, slip: Slip) -> String {
        let id8 = String(slip.id.uuidString.lowercased().prefix(8))
        let ext = (path as NSString).pathExtension
        let base = ext.isEmpty ? path : String(path.dropLast(ext.count + 1))
        let dir = (base as NSString).deletingLastPathComponent
        var file = (base as NSString).lastPathComponent
        let suffix = "_" + id8 + (ext.isEmpty ? "" : "." + ext)
        if file.count + suffix.count > maxComponentLength { file = String(file.prefix(maxComponentLength - suffix.count)) }
        return (dir.isEmpty ? "" : dir + "/") + file + suffix
    }

    /// The sidecar's path: the PDF's with `.json`.
    public static func sidecarPath(for pdfPath: String) -> String {
        ((pdfPath as NSString).deletingPathExtension) + ".json"
    }

    static func sanitize(_ value: String) -> String {
        let nfc = value.precomposedStringWithCanonicalMapping
        let replaced = String(String.UnicodeScalarView(nfc.unicodeScalars.map { forbidden.contains($0) ? "-" : $0 }))
        return replaced.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Trims spaces, dots, dashes and underscores at the ends (Windows and SMB refuse trailing dots
    /// and spaces; `..` must never survive) and collapses the `__` an empty token leaves.
    static func cleanComponent(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping
            .regexReplacing("_{2,}", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -_.").union(.whitespaces))
    }

    static func cap(_ component: String) -> String {
        guard component.count > maxComponentLength else { return component }
        let ext = (component as NSString).pathExtension
        guard !ext.isEmpty, ext.count < 10 else { return String(component.prefix(maxComponentLength)) }
        return String(component.prefix(maxComponentLength - ext.count - 1)) + "." + ext
    }

    /// `1234.5` style, never grouped, for file names (`43.67`).
    static func plainAmount(_ minor: Int, currency: String) -> String {
        let scale = Money.scale(for: currency)
        guard scale > 1 else { return String(minor) }
        let sign = minor < 0 ? "-" : ""
        let v = abs(minor)
        return "\(sign)\(v / scale).\(String(format: "%02d", v % scale))"
    }

    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
}

extension SlipLabels {
    static func resolve(for slip: Slip, in db: GRDB.Database) throws -> SlipLabels {
        var labels = SlipLabels()
        if let id = slip.enterpriseId { labels.business = try Enterprise.fetchOne(db, id: id)?.name }
        if let id = slip.subcategoryId, let sub = try Subcategory.fetchOne(db, id: id) {
            labels.subcategoryKey = sub.nameKey
            labels.subcategoryName = sub.customName
        }
        if let id = slip.paymentMethodId { labels.paymentMethod = try PaymentMethod.fetchOne(db, id: id)?.name }
        return labels
    }
}
