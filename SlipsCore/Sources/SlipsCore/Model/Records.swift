import Foundation
import GRDB

/// Shared column mapping: Swift camelCase properties, snake_case columns.
public protocol SlipsRecord: Codable, Sendable, FetchableRecord, PersistableRecord {}

extension SlipsRecord {
    public static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
    public static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
}

public struct Profile: SlipsRecord, Identifiable, Hashable {
    public static let databaseTableName = "profiles"
    public var id: UUID
    public var name: String
    public var mode: ProfileMode
    public var finBaseUrl: String?
    public var finWorkspaceId: String?
    public var finDeviceId: String?
    public var finUserDisplay: String?
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, mode: ProfileMode = .local, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.mode = mode
        self.createdAt = createdAt
    }
}

/// A business of the profile (fin's enterprise).
public struct Enterprise: SlipsRecord, Identifiable, Hashable {
    public static let databaseTableName = "enterprises"
    public var id: UUID
    public var profileId: UUID
    public var name: String
    public var remoteId: String?
    public var archivedAt: Date?

    public init(id: UUID = UUID(), profileId: UUID, name: String) {
        self.id = id
        self.profileId = profileId
        self.name = name
    }
}

public struct Subcategory: SlipsRecord, Identifiable, Hashable {
    public static let databaseTableName = "subcategories"
    public var id: UUID
    public var profileId: UUID
    public var kind: SubcategoryKind
    /// fin's stable key (`personal.groceries`) for a seeded row; nil for a custom one.
    public var nameKey: String?
    /// The user's name; overrides the translated name of `nameKey` when set.
    public var customName: String?
    public var sortOrder: Int
    public var remoteId: String?
    public var archivedAt: Date?

    public init(id: UUID = UUID(), profileId: UUID, kind: SubcategoryKind, nameKey: String? = nil,
                customName: String? = nil, sortOrder: Int = 0) {
        self.id = id
        self.profileId = profileId
        self.kind = kind
        self.nameKey = nameKey
        self.customName = customName
        self.sortOrder = sortOrder
    }
}

public struct PaymentMethod: SlipsRecord, Identifiable, Hashable {
    public static let databaseTableName = "payment_methods"
    public var id: UUID
    public var profileId: UUID
    public var name: String
    public var type: PaymentType
    public var last4: String?
    public var currency: String
    public var defaultKind: Kind?
    public var defaultEnterpriseId: UUID?
    public var remoteId: String?
    public var archivedAt: Date?

    public init(id: UUID = UUID(), profileId: UUID, name: String, type: PaymentType, last4: String? = nil,
                currency: String = "CAD", defaultKind: Kind? = nil, defaultEnterpriseId: UUID? = nil) {
        self.id = id
        self.profileId = profileId
        self.name = name
        self.type = type
        self.last4 = last4
        self.currency = currency
        self.defaultKind = defaultKind
        self.defaultEnterpriseId = defaultEnterpriseId
    }
}

public struct Slip: SlipsRecord, Identifiable, Hashable {
    public static let databaseTableName = "slips"
    /// The client UUID: also the idempotency key at every destination.
    public var id: UUID
    public var profileId: UUID
    public var status: SlipStatus
    public var capturedAt: Date
    /// Relative to the `FileStore` root: `Slips/<profile>/<slip>/slip.pdf`.
    public var pdfPath: String
    public var pdfSha256: String
    public var pageCount: Int
    public var ocrText: String?
    /// Raw parser output with confidences, JSON.
    public var extracted: String?
    public var merchant: String?
    public var txnDate: CalendarDay?
    public var currency: String
    public var subtotal: Int?
    public var gst: Int?
    public var qst: Int?
    public var hst: Int?
    public var tip: Int?
    public var total: Int?
    public var supplierGstNo: String?
    public var supplierQstNo: String?
    public var kind: Kind?
    public var enterpriseId: UUID?
    public var subcategoryId: UUID?
    public var paymentMethodId: UUID?
    public var notes: String?
    /// Results of `SlipChecks`, JSON.
    public var checks: String?
    public var updatedAt: Date

    public init(id: UUID = UUID(), profileId: UUID, status: SlipStatus = .draft, capturedAt: Date = Date(),
                pdfPath: String, pdfSha256: String, pageCount: Int, currency: String = "CAD") {
        self.id = id
        self.profileId = profileId
        self.status = status
        self.capturedAt = capturedAt
        self.pdfPath = pdfPath
        self.pdfSha256 = pdfSha256
        self.pageCount = pageCount
        self.currency = currency
        self.updatedAt = capturedAt
    }

    public func money(_ minorUnits: Int?) -> Money? {
        minorUnits.map { Money(minorUnits: $0, currency: currency) }
    }
}

/// What the profile last chose for a merchant; feeds the suggestions of the review screen.
public struct MerchantMemory: SlipsRecord, Hashable {
    public static let databaseTableName = "merchant_memory"
    public var profileId: UUID
    public var merchantNorm: String
    public var kind: Kind?
    public var enterpriseId: UUID?
    public var subcategoryId: UUID?
    public var paymentMethodId: UUID?
    public var uses: Int
    public var lastUsedAt: Date

    public init(profileId: UUID, merchantNorm: String, kind: Kind? = nil, enterpriseId: UUID? = nil,
                subcategoryId: UUID? = nil, paymentMethodId: UUID? = nil, uses: Int = 1, lastUsedAt: Date = Date()) {
        self.profileId = profileId
        self.merchantNorm = merchantNorm
        self.kind = kind
        self.enterpriseId = enterpriseId
        self.subcategoryId = subcategoryId
        self.paymentMethodId = paymentMethodId
        self.uses = uses
        self.lastUsedAt = lastUsedAt
    }
}

public struct Destination: SlipsRecord, Identifiable, Hashable {
    public static let databaseTableName = "destinations"
    public static let defaultNamingRule = "{business}/{year}/{date}_{merchant}_{total}.pdf"
    public var id: UUID
    public var profileId: UUID
    public var type: DestinationType
    public var name: String
    /// Type-specific settings, never a secret (secrets live in the Keychain, keyed by `id`).
    public var config: [String: String]
    public var namingRule: String
    public var wifiOnly: Bool
    public var enabled: Bool

    public init(id: UUID = UUID(), profileId: UUID, type: DestinationType, name: String,
                config: [String: String] = [:], namingRule: String = Destination.defaultNamingRule,
                wifiOnly: Bool = false, enabled: Bool = false) {
        self.id = id
        self.profileId = profileId
        self.type = type
        self.name = name
        self.config = config
        self.namingRule = namingRule
        self.wifiOnly = wifiOnly
        self.enabled = enabled
    }
}

/// One row per (slip, destination): the outbox.
public struct Delivery: SlipsRecord, Hashable {
    public static let databaseTableName = "deliveries"
    public var slipId: UUID
    public var destinationId: UUID
    public var status: DeliveryStatus
    public var attempts: Int
    public var nextAttemptAt: Date?
    public var lastErrorCode: String?
    public var remoteRef: String?
    public var deliveredSha256: String?
    public var updatedAt: Date

    public init(slipId: UUID, destinationId: UUID, status: DeliveryStatus = .pending, attempts: Int = 0,
                nextAttemptAt: Date? = nil, updatedAt: Date = Date()) {
        self.slipId = slipId
        self.destinationId = destinationId
        self.status = status
        self.attempts = attempts
        self.nextAttemptAt = nextAttemptAt
        self.updatedAt = updatedAt
    }
}
