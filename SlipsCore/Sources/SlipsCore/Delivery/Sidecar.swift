import Foundation

/// The JSON written next to a slip's PDF at destinations that keep one (`docs/SIDECAR.md`).
/// Version 1. Amounts are integer minor units; names are resolved, keys are fin's.
public struct Sidecar: Codable, Hashable, Sendable {
    public static let schema = "com.etzian.slips.sidecar/1"

    public var schema: String
    public var id: String
    public var pdfSha256: String
    public var pageCount: Int
    public var capturedAt: Date
    public var merchant: String?
    public var date: String?
    public var currency: String
    public var subtotal: Int?
    public var gst: Int?
    public var qst: Int?
    public var hst: Int?
    public var tip: Int?
    public var total: Int?
    public var supplierGstNo: String?
    public var supplierQstNo: String?
    public var kind: String?
    public var business: String?
    public var subcategoryKey: String?
    public var subcategoryName: String?
    public var paymentMethod: String?
    public var notes: String?
    public var checks: [String]

    public init(slip: Slip, labels: SlipLabels) {
        schema = Self.schema
        id = slip.id.uuidString.lowercased()
        pdfSha256 = slip.pdfSha256
        pageCount = slip.pageCount
        capturedAt = slip.capturedAt
        merchant = slip.merchant
        date = slip.txnDate?.iso
        currency = slip.currency
        subtotal = slip.subtotal
        gst = slip.gst
        qst = slip.qst
        hst = slip.hst
        tip = slip.tip
        total = slip.total
        supplierGstNo = slip.supplierGstNo
        supplierQstNo = slip.supplierQstNo
        kind = slip.kind?.rawValue
        business = labels.business
        subcategoryKey = labels.subcategoryKey
        subcategoryName = labels.subcategoryName
        paymentMethod = labels.paymentMethod
        notes = slip.notes
        checks = slip.decodedChecks.map(\.code)
    }

    enum CodingKeys: String, CodingKey {
        case schema, id, merchant, date, currency, subtotal, gst, qst, hst, tip, total, kind, business, notes, checks
        case pdfSha256 = "pdf_sha256", pageCount = "page_count", capturedAt = "captured_at"
        case supplierGstNo = "supplier_gst_no", supplierQstNo = "supplier_qst_no"
        case subcategoryKey = "subcategory_key", subcategoryName = "subcategory_name", paymentMethod = "payment_method"
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return try e.encode(self)
    }
}
