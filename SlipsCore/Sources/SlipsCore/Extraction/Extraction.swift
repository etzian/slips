import Foundation

/// One extracted value with how sure the parser is (0…1) and the row it came from.
public struct ExtractedField<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public var value: Value
    public var confidence: Double
    public var sourceLine: Int?
    public var sourceText: String?

    public init(value: Value, confidence: Double, sourceLine: Int? = nil, sourceText: String? = nil) {
        self.value = value
        self.confidence = confidence
        self.sourceLine = sourceLine
        self.sourceText = sourceText
    }

    /// Below this, the review screen highlights the field.
    public static var lowConfidence: Double { 0.6 }
    public var isLowConfidence: Bool { confidence < Self.lowConfidence }
}

/// The parser's output for every field of plan §4. Amounts are minor units in `currency`.
public struct Extraction: Codable, Hashable, Sendable {
    public var merchant: ExtractedField<String>?
    public var date: ExtractedField<CalendarDay>?
    public var subtotal: ExtractedField<Int>?
    public var gst: ExtractedField<Int>?
    public var qst: ExtractedField<Int>?
    public var hst: ExtractedField<Int>?
    public var tip: ExtractedField<Int>?
    public var total: ExtractedField<Int>?
    public var currency: ExtractedField<String>?
    public var cardLast4: ExtractedField<String>?
    public var supplierGstNo: ExtractedField<String>?
    public var supplierQstNo: ExtractedField<String>?

    public init() {}

    public var json: String {
        String(decoding: (try? JSONEncoder.sorted.encode(self)) ?? Data("{}".utf8), as: UTF8.self)
    }

    public static func from(json: String?) -> Extraction? {
        guard let data = json?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Extraction.self, from: data)
    }
}

extension Slip {
    /// Copies the extracted values into the slip's fields and keeps the raw output and OCR text.
    public mutating func apply(_ extraction: Extraction, ocrText: String) {
        self.ocrText = ocrText
        extracted = extraction.json
        merchant = extraction.merchant?.value
        txnDate = extraction.date?.value
        currency = extraction.currency?.value ?? currency
        subtotal = extraction.subtotal?.value
        gst = extraction.gst?.value
        qst = extraction.qst?.value
        hst = extraction.hst?.value
        tip = extraction.tip?.value
        total = extraction.total?.value
        supplierGstNo = extraction.supplierGstNo?.value
        supplierQstNo = extraction.supplierQstNo?.value
    }

    public var extraction: Extraction? { Extraction.from(json: extracted) }
}
