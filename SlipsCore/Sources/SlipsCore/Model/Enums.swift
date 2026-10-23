import GRDB

/// Fin's three categories. Slips calls them kinds; the raw values are fin's.
public enum Kind: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case personal, family, enterprise
}

/// A sub-category belongs to one kind, or to `any` (transfers, card payments).
public enum SubcategoryKind: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case personal, family, enterprise, any

    public init(_ kind: Kind) {
        switch kind {
        case .personal: self = .personal
        case .family: self = .family
        case .enterprise: self = .enterprise
        }
    }
}

public enum ProfileMode: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case local, fin
}

public enum PaymentType: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case creditCard = "credit_card"
    case debit, chequing, cash, other
}

public enum SlipStatus: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case draft, ready, archived
}

public enum DestinationType: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case library, icloud, folder, webdav, fin, dropbox, onedrive, gdrive
}

public enum DeliveryStatus: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case pending
    case inFlight = "in_flight"
    case done, failed
    case needsAuth = "needs_auth"
}
