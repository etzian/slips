import Foundation

/// Rule-based proofreading of a slip (plan §5): free, offline and explainable. Each rule is a pure
/// function of the slip and its context; `run` returns the findings, most severe first.
public enum SlipChecks {
    public struct Context: Sendable {
        public var today: CalendarDay
        /// Slips older than this many years get a warning (the profile's limit; 2 by default).
        public var maxAgeYears: Int
        /// Last fours of the profile's payment methods (archived ones included).
        public var knownLastFours: Set<String>
        /// Another slip of the profile has the same merchant, date and total.
        public var duplicateExists: Bool
        public var fileExists: Bool

        public init(today: CalendarDay, maxAgeYears: Int = 2, knownLastFours: Set<String> = [],
                    duplicateExists: Bool = false, fileExists: Bool = true) {
            self.today = today
            self.maxAgeYears = maxAgeYears
            self.knownLastFours = knownLastFours
            self.duplicateExists = duplicateExists
            self.fileExists = fileExists
        }
    }

    public enum Code {
        public static let totalMissing = "total_missing"
        public static let sumMismatch = "sum_mismatch"
        public static let taxRate = "tax_rate"
        public static let dateFuture = "date_future"
        public static let dateTooOld = "date_too_old"
        public static let cardUnknown = "card_unknown"
        public static let registrationMissing = "registration_missing"
        public static let duplicate = "duplicate"
        public static let fileMissing = "file_missing"
    }

    /// Cents of slack for rounding on sums.
    static let sumTolerance = 2

    public static func run(_ slip: Slip, context: Context) -> [Check] {
        let rules: [(Slip, Context) -> Check?] = [fileMissing, totalMissing, sumMismatch, taxRate, dateRange,
                                                  cardUnknown, registrationMissing, duplicate]
        return rules.compactMap { $0(slip, context) }
            .enumerated().sorted { ($0.element.severity, -$0.offset) > ($1.element.severity, -$1.offset) }.map(\.element)
    }

    static func fileMissing(_ slip: Slip, _ c: Context) -> Check? {
        c.fileExists ? nil : .fileMissing
    }

    static func totalMissing(_ slip: Slip, _ c: Context) -> Check? {
        slip.total == nil ? Check(code: Code.totalMissing, severity: .blocking) : nil
    }

    /// subtotal + taxes + tip ≠ total (± 0.02).
    static func sumMismatch(_ slip: Slip, _ c: Context) -> Check? {
        guard let subtotal = slip.subtotal, let total = slip.total else { return nil }
        let sum = subtotal + (slip.gst ?? 0) + (slip.qst ?? 0) + (slip.hst ?? 0) + (slip.tip ?? 0)
        guard abs(sum - total) > sumTolerance else { return nil }
        return Check(code: Code.sumMismatch, severity: .warning,
                     values: [.money(sum, currency: slip.currency), .money(total, currency: slip.currency)])
    }

    /// GST ≠ 5 % or QST ≠ 9.975 % of the taxable amount (± rounding), when both are present.
    static func taxRate(_ slip: Slip, _ c: Context) -> Check? {
        guard let gst = slip.gst, let qst = slip.qst else { return nil }
        let taxable: Int
        if let subtotal = slip.subtotal {
            taxable = subtotal
        } else if let total = slip.total {
            taxable = total - gst - qst - (slip.tip ?? 0)
        } else {
            return nil
        }
        let expectedGST = (Double(taxable) * 0.05).rounded()
        let expectedQST = (Double(taxable) * 0.09975).rounded()
        guard abs(Double(gst) - expectedGST) > 1 || abs(Double(qst) - expectedQST) > 1 else { return nil }
        return Check(code: Code.taxRate, severity: .info)
    }

    /// In the future, or older than the profile's limit.
    static func dateRange(_ slip: Slip, _ c: Context) -> Check? {
        guard let day = slip.txnDate else { return nil }
        if day > c.today {
            return Check(code: Code.dateFuture, severity: .warning, values: [.day(day)])
        }
        var limit = c.today
        limit.year -= c.maxAgeYears
        if limit.month == 2 && limit.day == 29 && CalendarDay(year: limit.year, month: 2, day: 29) == nil { limit.day = 28 }
        if day < limit {
            return Check(code: Code.dateTooOld, severity: .warning, values: [.day(day), .number(c.maxAgeYears)])
        }
        return nil
    }

    /// A card's last four was read but no payment method has it.
    static func cardUnknown(_ slip: Slip, _ c: Context) -> Check? {
        guard slip.paymentMethodId == nil, let last4 = slip.extraction?.cardLast4?.value,
              !c.knownLastFours.contains(last4) else { return nil }
        return Check(code: Code.cardUnknown, severity: .info, values: [.text(last4)])
    }

    /// A business slip without the supplier's registration numbers cannot back an input tax credit
    /// or refund above the thresholds. HST slips need the GST/HST number only.
    static func registrationMissing(_ slip: Slip, _ c: Context) -> Check? {
        guard slip.kind == .enterprise else { return nil }
        let gstMissing = (slip.supplierGstNo ?? "").isEmpty
        let qstMissing = slip.hst == nil && (slip.supplierQstNo ?? "").isEmpty
        guard gstMissing || qstMissing else { return nil }
        return Check(code: Code.registrationMissing, severity: .warning)
    }

    static func duplicate(_ slip: Slip, _ c: Context) -> Check? {
        c.duplicateExists ? Check(code: Code.duplicate, severity: .warning) : nil
    }
}
