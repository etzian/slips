import Foundation
import SlipsCore
import SwiftUI

// Translated names of core enums. Catalog keys are spelled out so the String Catalog tracks them.

extension Kind {
    var title: LocalizedStringKey {
        switch self {
        case .personal: "kind.personal"
        case .family: "kind.family"
        case .enterprise: "kind.enterprise"
        }
    }

    var text: String {
        switch self {
        case .personal: String(localized: "kind.personal")
        case .family: String(localized: "kind.family")
        case .enterprise: String(localized: "kind.enterprise")
        }
    }
}

extension SubcategoryKind {
    var title: LocalizedStringKey {
        switch self {
        case .personal: "kind.personal"
        case .family: "kind.family"
        case .enterprise: "kind.enterprise"
        case .any: "kind.any"
        }
    }
}

extension PaymentType {
    var title: LocalizedStringKey {
        switch self {
        case .creditCard: "paymentType.creditCard"
        case .debit: "paymentType.debit"
        case .chequing: "paymentType.chequing"
        case .cash: "paymentType.cash"
        case .other: "paymentType.other"
        }
    }
}

extension Subcategory {
    /// The user's name if set, else the translated name of fin's key.
    var displayName: String {
        if let custom = customName, !custom.isEmpty { return custom }
        guard let key = nameKey else { return "" }
        // Seeded keys are listed in the catalog as `subcategory.<fin key>`.
        return Bundle.main.localizedString(forKey: "subcategory.\(key)", value: key, table: nil)
    }
}

extension ValidationError {
    var message: LocalizedStringKey {
        switch self {
        case .blankName: "error.validation.blankName"
        case .invalidLastFour: "error.validation.lastFour"
        case .invalidCurrency: "error.validation.currency"
        case .archiveRefused: "error.validation.archiveRefused"
        case .notFound: "error.validation.notFound"
        }
    }
}
