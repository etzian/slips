import Foundation
import GRDB

/// CSV, JSON and ZIP exports of the library (plan §1 step 6, columns in `docs/EXPORT.md`).
public struct Exporter: Sendable {
    public let database: AppDatabase
    public let files: FileStore

    public init(database: AppDatabase, files: FileStore) {
        self.database = database
        self.files = files
    }

    /// One exported slip: its columns, resolved names, and the PDF's name inside a ZIP.
    public struct Row: Sendable, Hashable, Codable {
        public var id: String
        public var date: String
        public var merchant: String
        public var currency: String
        public var subtotal: String
        public var gst: String
        public var qst: String
        public var hst: String
        public var tip: String
        public var total: String
        public var kind: String
        public var business: String
        public var subcategoryKey: String
        public var subcategory: String
        public var paymentMethod: String
        public var supplierGstNo: String
        public var supplierQstNo: String
        public var notes: String
        public var status: String
        public var checks: String
        public var capturedAt: String
        public var pdfFile: String

        public static let columns = ["id", "date", "merchant", "currency", "subtotal", "gst", "qst", "hst", "tip", "total",
                                     "kind", "business", "subcategory_key", "subcategory", "payment_method", "supplier_gst_no",
                                     "supplier_qst_no", "notes", "status", "checks", "captured_at", "pdf_file"]

        var values: [String] {
            [id, date, merchant, currency, subtotal, gst, qst, hst, tip, total, kind, business, subcategoryKey, subcategory,
             paymentMethod, supplierGstNo, supplierQstNo, notes, status, checks, capturedAt, pdfFile]
        }

        enum CodingKeys: String, CodingKey {
            case id, date, merchant, currency, subtotal, gst, qst, hst, tip, total, kind, business, subcategory, notes, status, checks
            case subcategoryKey = "subcategory_key", paymentMethod = "payment_method", supplierGstNo = "supplier_gst_no"
            case supplierQstNo = "supplier_qst_no", capturedAt = "captured_at", pdfFile = "pdf_file"
        }
    }

    /// The rows of `items`, PDF names from the default naming rule (collisions get `_{id8}`).
    public func rows(_ items: [LibraryItem], localize: (String) -> String = { $0 }) throws -> [Row] {
        try database.writer.read { db in
            var used = Set<String>()
            return try items.map { item in
                let s = item.slip
                let labels = try SlipLabels.resolve(for: s, in: db)
                var pdf = NamingRule(NamingRule.defaultRule).path(for: s, labels: labels, localize: localize)
                if !used.insert(pdf.lowercased()).inserted {
                    pdf = NamingRule.withIdSuffix(pdf, slip: s)
                    used.insert(pdf.lowercased())
                }
                func amount(_ v: Int?) -> String { v.map { NamingRule.plainAmount($0, currency: s.currency) } ?? "" }
                let iso = ISO8601DateFormatter()
                return Row(id: s.id.uuidString.lowercased(), date: item.day.iso, merchant: s.merchant ?? "", currency: s.currency,
                           subtotal: amount(s.subtotal), gst: amount(s.gst), qst: amount(s.qst), hst: amount(s.hst),
                           tip: amount(s.tip), total: amount(s.total), kind: s.kind?.rawValue ?? "",
                           business: labels.business ?? "", subcategoryKey: labels.subcategoryKey ?? "",
                           subcategory: labels.subcategoryName ?? labels.subcategoryKey.map { localize("subcategory.\($0)") } ?? "",
                           paymentMethod: labels.paymentMethod ?? "", supplierGstNo: s.supplierGstNo ?? "",
                           supplierQstNo: s.supplierQstNo ?? "", notes: s.notes ?? "", status: s.status.rawValue,
                           checks: s.decodedChecks.map(\.code).joined(separator: " "), capturedAt: iso.string(from: s.capturedAt),
                           pdfFile: pdf)
            }
        }
    }

    /// RFC 4180 CSV, UTF-8 with a byte-order mark (spreadsheets then read accents right), CRLF.
    public static func csv(_ rows: [Row]) -> Data {
        var lines = [Row.columns.joined(separator: ",")]
        lines += rows.map { $0.values.map(csvField).joined(separator: ",") }
        return Data([0xEF, 0xBB, 0xBF]) + Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    /// Quotes a field when it holds a comma, a quote, a line break or leading/trailing spaces; a field
    /// starting with `= + - @` gets a leading `'` so a spreadsheet never runs it as a formula.
    static func csvField(_ value: String) -> String {
        var v = value
        if let first = v.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first), Double(v) == nil { v = "'" + v }
        let special = CharacterSet(charactersIn: ",\"\r\n")
        let needsQuotes = v.unicodeScalars.contains(where: special.contains) || v.hasPrefix(" ") || v.hasSuffix(" ")
        return needsQuotes ? "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : v
    }

    public static func json(_ rows: [Row]) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(rows)
    }

    /// Paths inside the ZIP: each PDF under its default-rule name, plus `slips.csv`.
    public static func manifest(_ rows: [Row]) -> [String] {
        rows.map(\.pdfFile) + ["slips.csv"]
    }

    /// The ZIP of the PDFs and the CSV. A slip whose PDF is missing is listed in the CSV only.
    public func zip(_ items: [LibraryItem], rows: [Row]) throws -> Data {
        var writer = ZipWriter()
        for (item, row) in Swift.zip(items, rows) {
            guard let pdf = try? files.read(item.slip.pdfPath) else { continue }
            try writer.add(row.pdfFile, contents: pdf, modified: item.slip.capturedAt)
        }
        try writer.add("slips.csv", contents: Self.csv(rows))
        return writer.finish()
    }
}
