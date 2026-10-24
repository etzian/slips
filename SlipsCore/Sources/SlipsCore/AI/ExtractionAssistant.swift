import Foundation

/// What an assistant is given: the slip's OCR text only, never the image.
public struct AssistantInput: Sendable, Hashable {
    public var ocrText: String
    /// The user's locale (`fr_CA`), for dates and decimal commas.
    public var localeIdentifier: String
    /// The currency the parser read, if any.
    public var currencyHint: String?
    /// When the slip was scanned, or the date in an imported file's name: the slip is from then or before.
    public var referenceDay: CalendarDay?

    public init(ocrText: String, localeIdentifier: String, currencyHint: String? = nil, referenceDay: CalendarDay? = nil) {
        self.ocrText = ocrText
        self.localeIdentifier = localeIdentifier
        self.currencyHint = currencyHint
        self.referenceDay = referenceDay
    }
}

/// An assistant's reading of a slip: the parser's fields, each with a confidence, plus a sub-category
/// suggestion among fin's keys.
public struct AIExtraction: Codable, Hashable, Sendable {
    public var merchant: ExtractedField<String>?
    public var date: ExtractedField<CalendarDay>?
    public var subtotal: ExtractedField<Int>?
    public var gst: ExtractedField<Int>?
    public var qst: ExtractedField<Int>?
    public var hst: ExtractedField<Int>?
    public var tip: ExtractedField<Int>?
    public var total: ExtractedField<Int>?
    public var currency: ExtractedField<String>?
    public var supplierGstNo: ExtractedField<String>?
    public var supplierQstNo: ExtractedField<String>?
    /// A key of `Seed.allKeys` (`personal.groceries`); anything else is dropped.
    public var subcategoryKey: ExtractedField<String>?

    public init() {}
}

/// A model that reads a slip: on-device (Foundation Models), or an endpoint the user consented to
/// (Ollama, Claude, OpenAI). Every implementation has a fake in the tests; no gate calls a model.
public protocol ExtractionAssistant: Sendable {
    /// Stable identifier stored with the result (`on_device`, `ollama`, `claude`, `openai`).
    var id: String { get }
    func extract(_ input: AssistantInput) async throws -> AIExtraction
}

/// What is stored in `slips.ai`: which assistant, when, what it read, which fields it filled.
public struct AIResult: Codable, Hashable, Sendable {
    public var assistant: String
    public var model: String?
    public var at: Date
    public var extraction: AIExtraction
    /// Fields the assistant filled on the slip (`total`, `date`…); the others stayed the parser's or the user's.
    public var filled: [String]

    public init(assistant: String, model: String? = nil, at: Date, extraction: AIExtraction, filled: [String] = []) {
        self.assistant = assistant
        self.model = model
        self.at = at
        self.extraction = extraction
        self.filled = filled
    }

    public var json: String {
        String(decoding: (try? JSONEncoder.sorted.encode(self)) ?? Data("{}".utf8), as: UTF8.self)
    }
}

extension Slip {
    public var aiResult: AIResult? {
        guard let data = ai?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AIResult.self, from: data)
    }
}

/// How an assistant's reading joins the slip (plan M2 P1): the parser stays the source; the assistant
/// fills a field only when the parser left it empty or unsure **and** the user has not changed it.
public enum AIMerge {
    /// The slip with gaps filled, and the names of the fields filled.
    public static func merge(_ ai: AIExtraction, into slip: Slip) -> (Slip, [String]) {
        var s = slip
        var filled: [String] = []
        let parsed = slip.extraction ?? Extraction()

        func fill<V: Equatable>(_ name: String, _ current: WritableKeyPath<Slip, V?>, parser: ExtractedField<V>?,
                                assistant: ExtractedField<V>?) {
            guard let suggestion = assistant?.value else { return }
            let value = s[keyPath: current]
            // The user typed something else than the parser read: theirs stands.
            if let value, value != parser?.value { return }
            let parserSure = parser.map { !$0.isLowConfidence } ?? false
            guard value == nil || !parserSure, value != suggestion else { return }
            s[keyPath: current] = suggestion
            filled.append(name)
        }

        fill("merchant", \.merchant, parser: parsed.merchant, assistant: ai.merchant)
        fill("date", \.txnDate, parser: parsed.date, assistant: ai.date)
        fill("subtotal", \.subtotal, parser: parsed.subtotal, assistant: ai.subtotal)
        fill("gst", \.gst, parser: parsed.gst, assistant: ai.gst)
        fill("qst", \.qst, parser: parsed.qst, assistant: ai.qst)
        fill("hst", \.hst, parser: parsed.hst, assistant: ai.hst)
        fill("tip", \.tip, parser: parsed.tip, assistant: ai.tip)
        fill("total", \.total, parser: parsed.total, assistant: ai.total)
        fill("supplier_gst_no", \.supplierGstNo, parser: parsed.supplierGstNo, assistant: ai.supplierGstNo)
        fill("supplier_qst_no", \.supplierQstNo, parser: parsed.supplierQstNo, assistant: ai.supplierQstNo)

        // A tax that is not printed is zero, not unknown: amounts that add up stay as they are. If the
        // assistant's amounts would break a slip that adds up, none of its amounts are taken.
        let amounts = ["subtotal", "gst", "qst", "hst", "tip", "total"]
        if filled.contains(where: amounts.contains), addsUp(slip), !addsUp(s) {
            s.subtotal = slip.subtotal
            s.gst = slip.gst
            s.qst = slip.qst
            s.hst = slip.hst
            s.tip = slip.tip
            s.total = slip.total
            filled.removeAll(where: amounts.contains)
        }
        return (s, filled)
    }

    /// Subtotal + taxes + tip = total (± 2 ¢) and no tax above its rate; true when there is no
    /// subtotal or no total to check.
    static func addsUp(_ s: Slip) -> Bool {
        var e = Extraction()
        e.subtotal = s.subtotal.map { ExtractedField(value: $0, confidence: 1) }
        e.gst = s.gst.map { ExtractedField(value: $0, confidence: 1) }
        e.qst = s.qst.map { ExtractedField(value: $0, confidence: 1) }
        e.hst = s.hst.map { ExtractedField(value: $0, confidence: 1) }
        e.tip = s.tip.map { ExtractedField(value: $0, confidence: 1) }
        e.total = s.total.map { ExtractedField(value: $0, confidence: 1) }
        return SlipParser.isConsistent(e)
    }

    /// The assistant's own amounts add up (or it gave too few to tell).
    static func selfConsistent(_ ai: AIExtraction) -> Bool {
        var e = Extraction()
        e.subtotal = ai.subtotal
        e.gst = ai.gst
        e.qst = ai.qst
        e.hst = ai.hst
        e.tip = ai.tip
        e.total = ai.total
        return SlipParser.isConsistent(e)
    }

    /// Drops what an assistant may not say: unknown sub-category keys, negative amounts, a currency
    /// that is not three letters.
    public static func sanitized(_ ai: AIExtraction) -> AIExtraction {
        var a = ai
        if let key = a.subcategoryKey?.value, !Seed.allKeys.contains(key) { a.subcategoryKey = nil }
        if let c = a.currency?.value, c.count != 3 || !c.allSatisfy({ $0.isASCII && $0.isLetter }) { a.currency = nil }
        for path in [\AIExtraction.subtotal, \.gst, \.qst, \.hst, \.tip, \.total] where (a[keyPath: path]?.value ?? 0) < 0 {
            a[keyPath: path] = nil
        }
        return a
    }
}
