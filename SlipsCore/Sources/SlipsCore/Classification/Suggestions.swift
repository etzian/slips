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

/// Pre-fill (plan P6): the card's last four picks the payment method and its default kind and
/// business; then the merchant's memory; then the profile's last used values. Each field takes the
/// first source that has a value consistent with the kind already chosen.
public enum Suggestions {
    public static func suggest(cardLast4: String?, merchant: String?, reference: ReferenceSnapshot,
                               memory: MerchantMemory?, lastUsed: MerchantMemory?) -> Classification {
        var c = Classification()
        let method = cardLast4.flatMap { l4 in reference.paymentMethods.first { $0.last4 == l4 } }
        let sources: [MerchantMemory?] = [memory, lastUsed]
        let activeEnterprises = Set(reference.enterprises.map(\.id))
        let activeMethods = Set(reference.paymentMethods.map(\.id))

        c.paymentMethodId = method?.id ?? sources.lazy.compactMap { $0?.paymentMethodId }.first { activeMethods.contains($0) }
        c.kind = method?.defaultKind ?? sources.lazy.compactMap { $0?.kind }.first
        if c.kind == .enterprise {
            let fromMethod = method?.defaultEnterpriseId.flatMap { activeEnterprises.contains($0) ? $0 : nil }
            c.enterpriseId = fromMethod ?? sources.lazy.compactMap { $0?.enterpriseId }.first { activeEnterprises.contains($0) }
        }
        if let kind = c.kind {
            let usable = Set(reference.subcategories(for: kind).map(\.id))
            c.subcategoryId = sources.lazy.compactMap { $0?.subcategoryId }.first { usable.contains($0) }
        }
        return c
    }
}
