import Foundation

/// Reads the fields of plan §4 out of OCR lines. Pure: the same lines always give the same extraction.
/// Each field has its own function over the reading rows; `parse` composes them.
public enum SlipParser {
    /// `today` decides between two readings of an ambiguous date (the one in the future loses).
    public static func parse(_ lines: [OCRLine], today: CalendarDay? = nil) -> Extraction {
        let rows = OCRRow.rows(from: lines).map(Row.init)
        var e = Extraction()
        e.currency = currency(rows)
        e.hst = taxAmount(rows, labels: Labels.hst)
        if e.hst == nil {
            e.gst = taxAmount(rows, labels: Labels.gst)
            e.qst = taxAmount(rows, labels: Labels.qst)
        }
        e.subtotal = labelledAmount(rows, labels: Labels.subtotal, excluding: [])
        e.tip = labelledAmount(rows, labels: Labels.tip, excluding: [])
        e.total = total(rows)
        e.date = date(rows, today: today)
        e.cardLast4 = cardLast4(rows)
        e.supplierGstNo = gstNumber(rows)
        e.supplierQstNo = qstNumber(rows)
        e.merchant = merchant(rows)
        return reconcile(e, rows)
    }

    /// The OCR text as one string, rows in reading order, for search and the `ocr_text` column.
    public static func text(of lines: [OCRLine]) -> String {
        OCRRow.rows(from: lines).map(\.text).joined(separator: "\n")
    }

    // MARK: - Rows

    /// A row with its matching form: upper case, no accents, dots inside abbreviations removed.
    struct Row {
        let row: OCRRow
        let norm: String

        init(_ row: OCRRow) {
            self.row = row
            norm = Row.normalize(row.text)
        }

        static func normalize(_ text: String) -> String {
            var s = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .uppercased()
            // T.P.S. → TPS, T.V.Q → TVQ: drop dots between single letters.
            s = s.regexReplacing(#"\b([A-Z])\.(?=[A-Z]\b)"#, with: "$1")
            s = s.regexReplacing(#"\b([A-Z]{2,4})\.(?=\s|$)"#, with: "$1")
            return s
        }

        func field<V>(_ value: V, _ confidence: Double) -> ExtractedField<V> {
            ExtractedField(value: value, confidence: (confidence * row.confidence * 100).rounded() / 100,
                           sourceLine: row.index, sourceText: row.text)
        }
    }

    enum Labels {
        static let total = [#"\bGRAND TOTAL\b"#, #"\bTOTAL\b"#, #"\bMONTANT DU\b"#, #"\bAMOUNT DUE\b"#, #"\bA PAYER\b"#,
                            #"\bBALANCE DUE\b"#, #"\bSOLDE\b"#]
        static let totalExclusions = [#"SOUS[ -]?TOTAL"#, #"SUB[ -]?TOTAL"#, #"TOTAL (DES )?TAXES?"#, #"TOTAL TAX"#,
                                      #"TOTAL (TPS|TVQ|TVH|GST|QST|HST)"#, #"TOTAL (DES )?ARTICLES"#, #"TOTAL ITEMS"#,
                                      #"NOMBRE"#, #"ECONOMIES"#, #"SAVINGS"#, #"POINTS"#]
        static let paymentFallback = [#"\bMONTANT\b"#, #"\bAMOUNT\b"#, #"\bACHAT\b"#, #"\bPURCHASE\b"#, #"\bVENTE\b"#, #"\bSALE\b"#]
        static let subtotal = [#"SOUS[ -]?TOTAL"#, #"SUB[ -]?TOTAL"#]
        static let gst = [#"\bTPS\b"#, #"\bGST\b"#]
        static let qst = [#"\bTVQ\b"#, #"\bQST\b"#]
        static let hst = [#"\bTVH\b"#, #"\bHST\b"#]
        static let tip = [#"\bPOURBOIRE\b"#, #"\bPOURB\b"#, #"\bTIP\b"#, #"\bGRATUITY\b"#, #"\bGRATIFICATION\b"#]
        /// Rows that carry a tax label but are about the registration number or a total of taxes.
        static let taxExclusions = [#"\bRT ?\d{4}\b"#, #"\bTQ ?\d{4}\b"#, #"\b(NO|NUMERO|REG|#)\b"#, #"TOTAL"#]
    }

    // MARK: - Amounts

    /// Two-decimal amounts in a string, in order: `12.34`, `12,34`, `1 234,56`, `1,234.56`, `$12.34`,
    /// `12,34 $`. Percentages and longer decimals are not amounts.
    static func amounts(in text: String) -> [Int] {
        let pattern = #"(?<![\d.,])(-?)\$?\s?(\d{1,3}(?:[ \x{00A0},.]\d{3})+|\d+)[.,](\d{2})(?![\d%])(?!\s?%)"#
        return text.regexMatches(pattern).compactMap { groups in
            let whole = groups[2].filter(\.isNumber)
            guard let units = Int(whole), let cents = Int(groups[3]) else { return nil }
            let value = units * 100 + cents
            return groups[1] == "-" ? -value : value
        }
    }

    /// The rightmost amount of the first row (from the bottom when `lastWins`) matching one of
    /// `labels` and none of `excluding`.
    static func labelledAmount(_ rows: [Row], labels: [String], excluding: [String], confidence: Double = 0.9) -> ExtractedField<Int>? {
        let candidates = rows.filter { r in
            labels.contains { r.norm.contains(regex: $0) } && !excluding.contains { r.norm.contains(regex: $0) }
        }
        for r in candidates {
            if let amount = amounts(in: r.row.text).last, amount >= 0 {
                return r.field(amount, confidence)
            }
        }
        return nil
    }

    static func taxAmount(_ rows: [Row], labels: [String]) -> ExtractedField<Int>? {
        labelledAmount(rows, labels: labels, excluding: Labels.taxExclusions)
    }

    /// The paid total: the largest amount on a TOTAL-like row (a restaurant slip prints the total
    /// before and after the tip). Falls back to the card slip's amount line with less confidence.
    static func total(_ rows: [Row]) -> ExtractedField<Int>? {
        let candidates = rows.compactMap { r -> (Row, Int)? in
            guard Labels.total.contains(where: { r.norm.contains(regex: $0) }),
                  !Labels.totalExclusions.contains(where: { r.norm.contains(regex: $0) }),
                  let amount = amounts(in: r.row.text).last, amount > 0
            else { return nil }
            return (r, amount)
        }
        if let best = candidates.max(by: { $0.1 < $1.1 }) {
            return best.0.field(best.1, 0.9)
        }
        return labelledAmount(rows, labels: Labels.paymentFallback, excluding: Labels.totalExclusions, confidence: 0.6)
    }

    // MARK: - Reconciliation

    /// Cents of slack: printed taxes are rounded per line, totals per slip.
    static let taxSlack = 1
    static let sumSlack = 2

    /// When the labelled amounts do not add up (a printer whose amount column sits half a line off its
    /// labels makes OCR pair each label with its neighbour's amount), looks for the one assignment of
    /// the amounts printed in the totals block that does: GST = 5 %, QST = 9.975 % (or HST = 13 % / 15 %)
    /// of the subtotal, and subtotal + taxes + tip = total. Applied only when exactly one exists.
    static func reconcile(_ e: Extraction, _ rows: [Row]) -> Extraction {
        guard let total = e.total?.value, !isConsistent(e) else { return e }
        let labelled = rows.filter { r in
            [Labels.subtotal, Labels.gst, Labels.qst, Labels.hst, Labels.tip, Labels.total].joined()
                .contains { r.norm.contains(regex: $0) }
        }
        guard let first = labelled.first?.row.index, let last = labelled.last?.row.index else { return e }
        let block = rows.filter { $0.row.index >= first - 2 && $0.row.index <= last + 1 }
        var candidates: [(Int, Row)] = []
        for r in block {
            for a in amounts(in: r.row.text) where a > 0 && !candidates.contains(where: { $0.0 == a }) {
                candidates.append((a, r))
            }
        }
        let tip = e.tip?.value ?? 0
        var solutions: [(sub: (Int, Row), taxes: [(Int, Row)], hst: Bool)] = []
        for sub in candidates where sub.0 < total {
            let expectedGST = Int((Double(sub.0) * 0.05).rounded())
            let expectedQST = Int((Double(sub.0) * 0.09975).rounded())
            let gst = candidates.first { abs($0.0 - expectedGST) <= taxSlack && $0.0 != sub.0 }
            let qst = candidates.first { abs($0.0 - expectedQST) <= taxSlack && $0.0 != sub.0 }
            if let gst, let qst, abs(sub.0 + gst.0 + qst.0 + tip - total) <= sumSlack {
                solutions.append((sub, [gst, qst], false))
            }
            for rate in [0.13, 0.15] {
                let expected = Int((Double(sub.0) * rate).rounded())
                if let hst = candidates.first(where: { abs($0.0 - expected) <= taxSlack && $0.0 != sub.0 }),
                   abs(sub.0 + hst.0 + tip - total) <= sumSlack {
                    solutions.append((sub, [hst], true))
                }
            }
        }
        guard solutions.count == 1, let s = solutions.first else { return e }
        var fixed = e
        fixed.subtotal = s.sub.1.field(s.sub.0, 0.85)
        if s.hst {
            fixed.hst = s.taxes[0].1.field(s.taxes[0].0, 0.85)
            fixed.gst = nil
            fixed.qst = nil
        } else {
            fixed.gst = s.taxes[0].1.field(s.taxes[0].0, 0.85)
            fixed.qst = s.taxes[1].1.field(s.taxes[1].0, 0.85)
            fixed.hst = nil
        }
        return fixed
    }

    /// Subtotal + taxes + tip = total, and no tax above its rate on the subtotal (zero-rated items make a
    /// tax lower, never higher). Amounts paired with the wrong labels still add up, since they are the
    /// same numbers; the rate bound is what catches them. True when there is no subtotal to check against.
    static func isConsistent(_ e: Extraction) -> Bool {
        guard let total = e.total?.value, let sub = e.subtotal?.value else { return true }
        let sum = sub + (e.gst?.value ?? 0) + (e.qst?.value ?? 0) + (e.hst?.value ?? 0) + (e.tip?.value ?? 0)
        guard abs(sum - total) <= sumSlack else { return false }
        func within(_ tax: Int?, _ rate: Double) -> Bool {
            guard let tax else { return true }
            return tax <= Int((Double(sub) * rate).rounded()) + taxSlack
        }
        return within(e.gst?.value, 0.05) && within(e.qst?.value, 0.09975) && within(e.hst?.value, 0.15)
    }

    // MARK: - Currency

    static func currency(_ rows: [Row]) -> ExtractedField<String> {
        let checks: [(String, String)] = [
            (#"\bUSD\b|\bUS ?\$|\$ ?US\b|\bU\.S\. ?DOLLARS?\b"#, "USD"),
            (#"\bEUR\b|€"#, "EUR"),
            (#"\bCAD\b|\bCDN\b|\bCA ?\$|\$ ?CA\b"#, "CAD"),
        ]
        for (pattern, code) in checks {
            if let r = rows.first(where: { $0.norm.contains(regex: pattern) }) {
                return r.field(code, 0.9)
            }
        }
        // No currency printed: a slip read in Canada defaults to CAD, with less confidence.
        return ExtractedField(value: "CAD", confidence: 0.7)
    }

    // MARK: - Dates

    static let frenchMonths: [String: Int] = [
        "JANV": 1, "JAN": 1, "FEVR": 2, "FEV": 2, "MARS": 3, "MAR": 3, "AVR": 4, "AVRIL": 4, "MAI": 5, "JUIN": 6,
        "JUIL": 7, "AOUT": 8, "SEPT": 9, "SEP": 9, "OCT": 10, "NOV": 11, "DEC": 12,
        "JANVIER": 1, "FEVRIER": 2, "JUILLET": 7, "SEPTEMBRE": 9, "OCTOBRE": 10, "NOVEMBRE": 11, "DECEMBRE": 12,
    ]
    static let englishMonths: [String: Int] = [
        "JAN": 1, "FEB": 2, "MAR": 3, "APR": 4, "MAY": 5, "JUN": 6, "JUL": 7, "AUG": 8, "SEP": 9, "SEPT": 9,
        "OCT": 10, "NOV": 11, "DEC": 12, "JANUARY": 1, "FEBRUARY": 2, "MARCH": 3, "APRIL": 4, "JUNE": 6,
        "JULY": 7, "AUGUST": 8, "SEPTEMBER": 9, "OCTOBER": 10, "NOVEMBER": 11, "DECEMBER": 12,
    ]

    /// The first date in reading order, rows labelled DATE first. Formats: `2026-10-20`, `2026/10/20`,
    /// `20/10/2026`, `10/20/26`, `20 oct. 2026`, `Oct 20, 2026`, `20-OCT-26`.
    static func date(_ rows: [Row], today: CalendarDay?) -> ExtractedField<CalendarDay>? {
        let labelled = rows.filter { $0.norm.contains(regex: #"\bDATE\b"#) }
        for r in labelled + rows {
            if let (day, confidence) = date(in: r.norm, today: today) {
                return r.field(day, confidence)
            }
        }
        return nil
    }

    static func date(in text: String, today: CalendarDay?) -> (CalendarDay, Double)? {
        // ISO-like, year first.
        if let g = text.regexFirstMatch(#"(?<!\d)(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})(?!\d)"#),
           let d = CalendarDay(year: Int(g[1])!, month: Int(g[2])!, day: Int(g[3])!) {
            return (d, 0.95)
        }
        // Day and month names.
        if let g = text.regexFirstMatch(#"(?<!\d)(\d{1,2})[ -]?([A-Z]{3,9})\.?[ -]?(\d{4}|\d{2})(?!\d)"#),
           let month = frenchMonths[g[2]] ?? englishMonths[g[2]],
           let d = CalendarDay(year: fullYear(g[3]), month: month, day: Int(g[1])!) {
            return (d, 0.9)
        }
        if let g = text.regexFirstMatch(#"\b([A-Z]{3,9})\.? (\d{1,2}),? (\d{4})(?!\d)"#),
           let month = englishMonths[g[1]],
           let d = CalendarDay(year: Int(g[3])!, month: month, day: Int(g[2])!) {
            return (d, 0.9)
        }
        // Numeric, year last: day/month or month/day.
        if let g = text.regexFirstMatch(#"(?<![\d.,])(\d{1,2})[-/.](\d{1,2})[-/.](\d{4}|\d{2})(?![\d.,]\d)"#) {
            let a = Int(g[1])!, b = Int(g[2])!, year = fullYear(g[3])
            let dayFirst = CalendarDay(year: year, month: b, day: a)
            let monthFirst = CalendarDay(year: year, month: a, day: b)
            switch (dayFirst, monthFirst) {
            case let (d?, nil): return (d, 0.9)
            case let (nil, m?): return (m, 0.9)
            case let (d?, m?) where d == m: return (d, 0.9)
            case let (d?, m?):
                if let today {
                    if d > today && m <= today { return (m, 0.7) }
                    if m > today && d <= today { return (d, 0.7) }
                }
                // Both readings possible: a two-digit year is the US-style terminal (MM/DD/YY),
                // a four-digit year the Québec style (DD/MM/YYYY).
                return g[3].count == 2 ? (m, 0.5) : (d, 0.5)
            default: return nil
            }
        }
        return nil
    }

    static func fullYear(_ s: String) -> Int {
        let y = Int(s) ?? 0
        return s.count == 2 ? 2000 + y : y
    }

    // MARK: - Card and registration numbers

    /// The last four digits after a mask: `****1234`, `XXXXXXXXXXXX1234`, `•••• 1234`.
    static func cardLast4(_ rows: [Row]) -> ExtractedField<String>? {
        for r in rows {
            if let g = r.row.text.regexFirstMatch(#"(?:[*Xx•#]{4,}[ -]?)+(\d{4})(?!\d)"#) {
                return r.field(g[1], 0.95)
            }
        }
        return nil
    }

    /// Business number + `RT` program account: `123456789 RT0001`.
    static func gstNumber(_ rows: [Row]) -> ExtractedField<String>? {
        for r in rows {
            if let g = r.norm.regexFirstMatch(#"(?<!\d)(\d{9}) ?RT ?(\d{4})(?!\d)"#) {
                return r.field("\(g[1]) RT\(g[2])", 0.95)
            }
        }
        // Many terminals print only the 9-digit business number after the label ("TPS: 123456789").
        for r in rows {
            if let g = r.norm.regexFirstMatch(#"\b(?:TPS|GST|TPS/TVH|GST/HST)\b\s*(?:NO|#|:)?\s*:?\s*(\d{9})(?!\d)"#) {
                return r.field(g[1], 0.8)
            }
        }
        return nil
    }

    /// Québec registration: `1234567890 TQ0001`.
    static func qstNumber(_ rows: [Row]) -> ExtractedField<String>? {
        for r in rows {
            if let g = r.norm.regexFirstMatch(#"(?<!\d)(\d{10}) ?TQ ?(\d{4})(?!\d)"#) {
                return r.field("\(g[1]) TQ\(g[2])", 0.95)
            }
        }
        return nil
    }

    // MARK: - Merchant

    static let merchantSkip = [#"^(BIENVENUE|WELCOME|MERCI|THANK)"#, #"\b(RECU|RECEIPT|FACTURE|INVOICE|COPIE|COPY|CLIENT|CUSTOMER|TRANSACTION)\b"#,
                               #"\b(TEL|TELEPHONE|PHONE|WWW|HTTP|\.COM|\.CA)\b"#, #"^\d"#, #"\b(RUE|ST|AVE|AVENUE|BOUL|BLVD|ROAD|RD|CHEMIN|QC|ON)\b"#]

    /// The first wordy row near the top of the first page: the store's name on almost every slip.
    static func merchant(_ rows: [Row]) -> ExtractedField<String>? {
        let top = rows.filter { $0.row.page == 0 }.prefix(6)
        for (i, r) in top.enumerated() {
            let letters = r.row.text.filter(\.isLetter).count
            let digits = r.row.text.filter(\.isNumber).count
            guard letters >= 3, digits * 2 <= letters,
                  !merchantSkip.contains(where: { r.norm.contains(regex: $0) }),
                  date(in: r.norm, today: nil) == nil, amounts(in: r.row.text).isEmpty
            else { continue }
            let name = r.row.text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            return r.field(name, i == 0 ? 0.8 : 0.6)
        }
        return nil
    }
}

// MARK: - Regex helpers (NSRegularExpression works the same on Apple platforms and Linux)

extension String {
    func contains(regex pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }

    /// Capture groups of the first match; group 0 is the whole match, a missing group is "".
    func regexFirstMatch(_ pattern: String) -> [String]? {
        regexMatches(pattern).first
    }

    func regexMatches(_ pattern: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = self as NSString
        return re.matches(in: self, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }

    func regexReplacing(_ pattern: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return self }
        return re.stringByReplacingMatches(in: self, range: NSRange(location: 0, length: (self as NSString).length), withTemplate: template)
    }
}
