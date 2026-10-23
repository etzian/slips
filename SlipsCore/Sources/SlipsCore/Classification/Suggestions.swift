import Foundation
import GRDB

/// What the review screen's pickers start with.
public struct Classification: Hashable, Sendable {
    public var kind: Kind?
    public var enterpriseId: UUID?
    public var subcategoryId: UUID?
    public var paymentMethodId: UUID?

    public init(kind: Kind? = nil, enterpriseId: UUID? = nil, subcategoryId: UUID? = nil, paymentMethodId: UUID? = nil) {
        self.kind = kind
        self.enterpriseId = enterpriseId
        self.subcategoryId = subcategoryId
        self.paymentMethodId = paymentMethodId
    }
}

/// One filed slip as the suggestions see it.
public struct HistoryEntry: Sendable, Hashable {
    public var merchantNorm: String
    public var day: CalendarDay
    public var total: Int?
    public var kind: Kind?
    public var enterpriseId: UUID?
    public var subcategoryId: UUID?
    public var paymentMethodId: UUID?

    public init(merchantNorm: String, day: CalendarDay, total: Int? = nil, kind: Kind? = nil, enterpriseId: UUID? = nil,
                subcategoryId: UUID? = nil, paymentMethodId: UUID? = nil) {
        self.merchantNorm = merchantNorm
        self.day = day
        self.total = total
        self.kind = kind
        self.enterpriseId = enterpriseId
        self.subcategoryId = subcategoryId
        self.paymentMethodId = paymentMethodId
    }
}

/// Why a picker was pre-filled, shown under it on the review screen.
public enum SuggestionReason: Hashable, Sendable {
    /// The card's last four matched a payment method (and its defaults).
    case card(String)
    /// Most of the profile's filed slips from this merchant (`count` of them) used this value.
    case merchantHistory(Int)
    /// Filed slips with a similar amount and the same payment method used this value.
    case similarAmount
    /// The profile's most recent filed slip.
    case lastUsed
    /// The AI assistant's sub-category.
    case ai
}

public enum SuggestedField: String, Hashable, Sendable, CaseIterable {
    case kind, business, subcategory, paymentMethod
}

public struct Suggestion: Hashable, Sendable {
    public var classification = Classification()
    public var reasons: [SuggestedField: SuggestionReason] = [:]
    public init() {}
}

/// Pre-fill (M1 P6, ranked in M2 P3). Sources, in order, each field taking the first that offers a
/// value that is active and fits the kind already chosen:
/// 1. the card's last four → its payment method and that method's default kind and business;
/// 2. the profile's filed slips from the same merchant, weighted by recency (half-life 90 days);
/// 3. filed slips with a similar total (±25 %) paid with the same method, at a lower weight;
/// 4. the most recent filed slip;
/// 5. for the sub-category only, the AI assistant's key.
public enum Suggestions {
    public static let halfLifeDays = 90.0
    public static let amountTolerance = 0.25

    public static func suggest(cardLast4: String?, merchant: String?, total: Int?, aiSubcategoryKey: String?,
                               reference: ReferenceSnapshot, history: [HistoryEntry], today: CalendarDay) -> Suggestion {
        var out = Suggestion()
        let method = cardLast4.flatMap { l4 in reference.paymentMethods.first { $0.last4 == l4 } }
        let activeEnterprises = Set(reference.enterprises.map(\.id))
        let activeMethods = Set(reference.paymentMethods.map(\.id))

        // The tiers of history, best first, each with its reason.
        let norm = merchant.map(MerchantName.normalize) ?? ""
        let byMerchant = norm.isEmpty ? [] : history.filter { $0.merchantNorm == norm }
        let byAmount: [HistoryEntry] = total.map { t in
            history.filter { h in
                guard let ht = h.total, ht > 0 else { return false }
                let close = abs(Double(ht - t)) <= Double(max(ht, t)) * amountTolerance
                return close && (method == nil || h.paymentMethodId == method?.id)
            }
        } ?? []
        let latest = history.max { $0.day < $1.day }.map { [$0] } ?? []
        let tiers: [([HistoryEntry], SuggestionReason)] = [
            (byMerchant, .merchantHistory(byMerchant.count)), (byAmount, .similarAmount), (latest, .lastUsed),
        ]

        func best<V: Hashable>(_ value: (HistoryEntry) -> V?, allowed: (V) -> Bool) -> (V, SuggestionReason)? {
            for (entries, reason) in tiers {
                var score: [V: (Double, CalendarDay)] = [:]
                for e in entries {
                    guard let v = value(e), allowed(v) else { continue }
                    let w = weight(e.day, today: today)
                    let old = score[v] ?? (0, e.day)
                    score[v] = (old.0 + w, max(old.1, e.day))
                }
                // Highest weight; on a tie, the value used most recently.
                if let top = score.max(by: { ($0.value.0, $0.value.1) < ($1.value.0, $1.value.1) }) {
                    return (top.key, reason)
                }
            }
            return nil
        }

        if let method {
            out.classification.paymentMethodId = method.id
            out.reasons[.paymentMethod] = .card(cardLast4 ?? "")
        } else if let (id, why) = best({ $0.paymentMethodId }, allowed: activeMethods.contains) {
            out.classification.paymentMethodId = id
            out.reasons[.paymentMethod] = why
        }

        if let k = method?.defaultKind {
            out.classification.kind = k
            out.reasons[.kind] = .card(cardLast4 ?? "")
        } else if let (k, why) = best({ $0.kind }, allowed: { _ in true }) {
            out.classification.kind = k
            out.reasons[.kind] = why
        }
        guard let kind = out.classification.kind else { return out }

        if kind == .enterprise {
            if let e = method?.defaultEnterpriseId, activeEnterprises.contains(e) {
                out.classification.enterpriseId = e
                out.reasons[.business] = .card(cardLast4 ?? "")
            } else if let (e, why) = best({ $0.kind == .enterprise ? $0.enterpriseId : nil }, allowed: activeEnterprises.contains) {
                out.classification.enterpriseId = e
                out.reasons[.business] = why
            }
        }

        let usable = reference.subcategories(for: kind)
        let usableIds = Set(usable.map(\.id))
        if let (sub, why) = best({ $0.subcategoryId }, allowed: usableIds.contains) {
            out.classification.subcategoryId = sub
            out.reasons[.subcategory] = why
        } else if let key = aiSubcategoryKey, let sub = usable.first(where: { $0.nameKey == key }) {
            out.classification.subcategoryId = sub.id
            out.reasons[.subcategory] = .ai
        }
        return out
    }

    /// 1 today, ½ after `halfLifeDays`, ¼ after twice that.
    static func weight(_ day: CalendarDay, today: CalendarDay) -> Double {
        let utc = NamingRule.utc
        let days = utc.dateComponents([.day], from: day.date(in: utc), to: today.date(in: utc)).day ?? 0
        return pow(0.5, Double(max(days, 0)) / halfLifeDays)
    }
}
