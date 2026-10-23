/// The seed list of sub-categories, copied from fin's `packages/shared/src/categories.ts`
/// (`SEED_SUBCATEGORIES`, read 2026-10-23 at fin d406d36). Keys are fin's stable identities, so a local
/// profile linked to fin later maps by key. Keep the order: it is the default `sort_order`.
public enum Seed {
    public static let subcategoryKeys: [(kind: SubcategoryKind, keys: [String])] = [
        (.personal, [
            "personal.groceries", "personal.dining", "personal.transport", "personal.health",
            "personal.clothing", "personal.subscriptions", "personal.leisure", "personal.other",
        ]),
        (.family, [
            "family.housing", "family.utilities", "family.insurance", "family.childcare",
            "family.groceries", "family.vacations", "family.other",
        ]),
        (.enterprise, [
            "enterprise.revenue", "enterprise.supplies", "enterprise.software",
            "enterprise.professional_fees", "enterprise.travel", "enterprise.vehicle",
            "enterprise.bank_fees", "enterprise.taxes", "enterprise.payroll", "enterprise.other",
        ]),
        (.any, ["any.transfer", "any.card_payment"]),
    ]

    /// fin's `TRANSFER_KEYS`: not income or spending, never archived.
    public static let transferKeys: Set<String> = ["any.transfer", "any.card_payment"]

    public static var allKeys: [String] { subcategoryKeys.flatMap(\.keys) }
}
