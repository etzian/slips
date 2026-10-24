import Foundation

/// The words every assistant gets, and the shape of its answer. One prompt for the on-device model and
/// the endpoints, so they can be compared (M2 P8).
public enum AssistantPrompt {
    /// Bump when the instructions or the answer shape change; stored with consent (M2 P4).
    public static let version = 1

    public static var instructions: String {
        """
        You read the text of a purchase slip or bill from Québec or elsewhere in Canada, recognised by OCR. \
        Answer only with the requested fields. Use null when a field is not printed; never guess. \
        Amounts are what is printed, as numbers with a dot for decimals (12.34), without currency signs. \
        "TPS"/"GST" is the 5 % federal tax, "TVQ"/"QST" the 9.975 % Québec tax, "TVH"/"HST" the harmonised tax. \
        "total" is the amount paid, including tip. A tax that is not printed is null, never computed. The date is the transaction date, as YYYY-MM-DD. \
        GST numbers look like 123456789 RT0001, QST numbers like 1234567890 TQ0001. \
        For subcategory_key, choose the best fitting key from this list, or null: \(Seed.allKeys.joined(separator: ", ")).
        """
    }

    /// The user turn: the OCR text and the hints, nothing else.
    public static func message(_ input: AssistantInput) -> String {
        var text = "Locale: \(input.localeIdentifier)\n"
        if let c = input.currencyHint { text += "Currency printed or assumed: \(c)\n" }
        if let d = input.referenceDay {
            text += "Scanned or saved around \(d.iso); the date printed on the slip is what counts, usually close to that day. "
            text += "Numeric dates may be DD/MM/YY, MM/DD/YY or YY/MM/DD: choose the reading closest to that day.\n"
        }
        return text + "Slip text:\n" + input.ocrText
    }

    /// Field names of the answer, for JSON schemas (Ollama `format`, Claude tool, OpenAI `json_schema`).
    public static let fields: [(name: String, type: String, description: String)] = [
        ("merchant", "string", "Store or company name"),
        ("date", "string", "Transaction date, YYYY-MM-DD"),
        ("subtotal", "number", "Subtotal before taxes"),
        ("gst", "number", "GST / TPS amount"),
        ("qst", "number", "QST / TVQ amount"),
        ("hst", "number", "HST / TVH amount"),
        ("tip", "number", "Tip / pourboire"),
        ("total", "number", "Total paid"),
        ("currency", "string", "ISO 4217 code such as CAD or USD"),
        ("supplier_gst_no", "string", "Supplier GST number"),
        ("supplier_qst_no", "string", "Supplier QST number"),
        ("subcategory_key", "string", "One key from the list, or null"),
    ]

    /// A JSON Schema object for the answer: every field present, each a value or null (`anyOf`, the
    /// form structured outputs accept), no other key.
    public static var jsonSchema: [String: Any] {
        var properties: [String: Any] = [:]
        for f in fields {
            properties[f.name] = ["anyOf": [["type": f.type], ["type": "null"]], "description": f.description]
        }
        return ["type": "object", "properties": properties, "required": fields.map(\.name), "additionalProperties": false]
    }
}

/// An assistant's answer as plain values, from JSON (endpoints) or from the on-device `@Generable` type.
public struct AssistantReading: Codable, Hashable, Sendable {
    public var merchant: String?
    public var date: String?
    public var subtotal: Decimal?
    public var gst: Decimal?
    public var qst: Decimal?
    public var hst: Decimal?
    public var tip: Decimal?
    public var total: Decimal?
    public var currency: String?
    public var supplierGstNo: String?
    public var supplierQstNo: String?
    public var subcategoryKey: String?

    public init(merchant: String? = nil, date: String? = nil, subtotal: Decimal? = nil, gst: Decimal? = nil, qst: Decimal? = nil,
                hst: Decimal? = nil, tip: Decimal? = nil, total: Decimal? = nil, currency: String? = nil,
                supplierGstNo: String? = nil, supplierQstNo: String? = nil, subcategoryKey: String? = nil) {
        self.merchant = merchant
        self.date = date
        self.subtotal = subtotal
        self.gst = gst
        self.qst = qst
        self.hst = hst
        self.tip = tip
        self.total = total
        self.currency = currency
        self.supplierGstNo = supplierGstNo
        self.supplierQstNo = supplierQstNo
        self.subcategoryKey = subcategoryKey
    }

    enum CodingKeys: String, CodingKey {
        case merchant, date, subtotal, gst, qst, hst, tip, total, currency
        case supplierGstNo = "supplier_gst_no", supplierQstNo = "supplier_qst_no", subcategoryKey = "subcategory_key"
    }

    /// Lenient: numbers may come as numbers or strings ("12,34", "$12.34"); a bad field is dropped,
    /// never the whole answer.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func string(_ k: CodingKeys) -> String? {
            (try? c.decodeIfPresent(String.self, forKey: k)).flatMap { $0 }.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        }
        func number(_ k: CodingKeys) -> Decimal? {
            if let d = (try? c.decodeIfPresent(Decimal.self, forKey: k)).flatMap({ $0 }) { return d }
            return string(k).flatMap(Self.decimal(from:))
        }
        merchant = string(.merchant)
        date = string(.date)
        subtotal = number(.subtotal)
        gst = number(.gst)
        qst = number(.qst)
        hst = number(.hst)
        tip = number(.tip)
        total = number(.total)
        currency = string(.currency)?.uppercased()
        supplierGstNo = string(.supplierGstNo)
        supplierQstNo = string(.supplierQstNo)
        subcategoryKey = string(.subcategoryKey)
    }

    public static func decimal(from text: String) -> Decimal? {
        let cleaned = text.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
        let normal = cleaned.contains(".") ? cleaned.replacingOccurrences(of: ",", with: "") : cleaned.replacingOccurrences(of: ",", with: ".")
        return Decimal(string: normal, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Decodes a model's JSON answer, tolerating a Markdown code fence around it.
    public static func decode(_ text: String) -> AssistantReading? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n")
            if let end = t.range(of: "```", options: .backwards) { t = String(t[..<end.lowerBound]) }
        }
        guard let start = t.firstIndex(of: "{"), let end = t.lastIndex(of: "}") else { return nil }
        return try? JSONDecoder().decode(AssistantReading.self, from: Data(t[start...end].utf8))
    }

    /// The reading as an `AIExtraction`, amounts in minor units of `currency` (or `fallbackCurrency`),
    /// every field with the same confidence (models do not give one per field).
    public func extraction(fallbackCurrency: String = "CAD", confidence: Double = 0.7) -> AIExtraction {
        let code = (currency?.count == 3 ? currency : nil) ?? fallbackCurrency
        func f<V>(_ v: V?) -> ExtractedField<V>? { v.map { ExtractedField(value: $0, confidence: confidence) } }
        func money(_ d: Decimal?) -> ExtractedField<Int>? { f(d.map { Money.minorUnits(from: $0, currency: code) }) }
        var e = AIExtraction()
        e.merchant = f(merchant)
        e.date = f(date.flatMap(CalendarDay.init(iso:)))
        e.subtotal = money(subtotal)
        e.gst = money(gst)
        e.qst = money(qst)
        e.hst = money(hst)
        e.tip = money(tip)
        e.total = money(total)
        e.currency = f(currency)
        e.supplierGstNo = f(supplierGstNo)
        e.supplierQstNo = f(supplierQstNo)
        e.subcategoryKey = f(subcategoryKey)
        return AIMerge.sanitized(e)
    }
}
