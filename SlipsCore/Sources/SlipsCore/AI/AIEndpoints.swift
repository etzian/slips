import Foundation
import GRDB

public enum AIProvider: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case off, ollama, claude, openai

    /// Where the text goes: the user's own server, or a company outside Québec.
    public var isThirdParty: Bool { self == .claude || self == .openai }
    public var needsKey: Bool { self == .claude || self == .openai }
}

/// When an endpoint reads a slip: only when the user taps "Ask…", or every slip after capture.
public enum AIScope: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case onRequest = "on_request"
    case everySlip = "every_slip"
}

/// A profile's optional AI endpoint and the consent given for it.
public struct AIEndpointSettings: SlipsRecord, Hashable {
    public static let databaseTableName = "ai_endpoints"
    /// Bump when what is sent changes in a way the user must see again (with `AssistantPrompt.version`).
    public static let consentVersion = 1

    public var profileId: UUID
    public var provider: AIProvider
    public var baseUrl: String?
    public var model: String?
    public var localNetwork: Bool
    public var scope: AIScope
    public var consentProvider: AIProvider?
    public var consentScope: AIScope?
    public var consentVersion: Int?
    public var consentAt: Date?
    public var updatedAt: Date

    public init(profileId: UUID, provider: AIProvider = .off, baseUrl: String? = nil, model: String? = nil,
                localNetwork: Bool = false, scope: AIScope = .onRequest, updatedAt: Date = Date()) {
        self.profileId = profileId
        self.provider = provider
        self.baseUrl = baseUrl
        self.model = model
        self.localNetwork = localNetwork
        self.scope = scope
        self.updatedAt = updatedAt
    }

    /// The version the consent screen shows now: what is sent and how it is asked.
    public static var currentVersion: Int { consentVersion * 1000 + AssistantPrompt.version }

    /// Consent holds only for the provider, scope and version it was given for.
    public var hasConsent: Bool {
        provider != .off && consentProvider == provider && consentScope == scope && consentVersion == Self.currentVersion
            && consentAt != nil
    }
}

/// Settings and consent of the profiles' AI endpoints.
public struct AIEndpointStore: Sendable {
    public let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func settings(profile: UUID) throws -> AIEndpointSettings {
        try database.writer.read { db in try AIEndpointSettings.fetchOne(db, key: profile) } ?? AIEndpointSettings(profileId: profile)
    }

    public func observe(profile: UUID) -> AsyncThrowingStream<AIEndpointSettings, any Error> {
        database.observe { db in try AIEndpointSettings.fetchOne(db, key: profile) ?? AIEndpointSettings(profileId: profile) }
    }

    /// Saves the choice. A different provider or scope drops the consent: it must be given again.
    public func save(_ settings: AIEndpointSettings, now: Date = Date()) throws {
        var s = settings
        s.updatedAt = now
        if s.provider == .off || s.consentProvider != s.provider || s.consentScope != s.scope {
            s.consentProvider = nil
            s.consentScope = nil
            s.consentVersion = nil
            s.consentAt = nil
        }
        let saved = s
        try database.writer.write { db in try saved.save(db) }
    }

    /// Records the user's consent to the settings as they are now.
    public func consent(profile: UUID, now: Date = Date()) throws {
        try database.writer.write { db in
            guard var s = try AIEndpointSettings.fetchOne(db, key: profile), s.provider != .off else { throw ValidationError.notFound }
            s.consentProvider = s.provider
            s.consentScope = s.scope
            s.consentVersion = AIEndpointSettings.currentVersion
            s.consentAt = now
            s.updatedAt = now
            try s.update(db)
        }
    }

    /// Withdraws: provider off, consent gone. The app deletes the key from the Keychain.
    public func withdraw(profile: UUID, now: Date = Date()) throws {
        try save(AIEndpointSettings(profileId: profile, updatedAt: now), now: now)
    }
}

/// What may leave the phone for an endpoint: the OCR text with every long digit run reduced to its
/// last four. Never the image, the notes, or the names of profiles, businesses or payment methods.
public enum AIPrivacy {
    /// 12 or more digits, separators allowed (card, loyalty or account numbers): all but the last four
    /// become `•`. Registration numbers (9 or 10 digits) and amounts are shorter and stay.
    public static func mask(_ text: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"(?<!\d)(?:\d[ -]?){11,}\d(?!\d)"#) else { return text }
        let ns = text as NSString
        var out = text
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let run = ns.substring(with: m.range)
            let digits = run.filter(\.isNumber)
            let masked = String(repeating: "•", count: digits.count - 4) + digits.suffix(4)
            out = (out as NSString).replacingCharacters(in: m.range, with: masked)
        }
        return out
    }

    /// The input an endpoint gets for `slip`.
    public static func input(for slip: Slip, reference: CalendarDay? = nil, locale: String) -> AssistantInput? {
        guard let text = slip.ocrText, !text.isEmpty else { return nil }
        return AssistantInput(ocrText: mask(text), localeIdentifier: locale, currencyHint: slip.currency, referenceDay: reference)
    }
}

/// The one way to an endpoint: it hands one out only when the profile chose a provider, consented to
/// it, and the trigger fits the scope. The adapters are built by `factory` (Ollama, Claude, OpenAI).
public struct AssistantRouter: Sendable {
    public enum Trigger: Sendable { case automatic, userRequest }
    public typealias Factory = @Sendable (AIEndpointSettings) -> (any ExtractionAssistant)?

    public let store: AIEndpointStore
    public let factory: Factory

    public init(store: AIEndpointStore, factory: @escaping Factory) {
        self.store = store
        self.factory = factory
    }

    public func endpoint(profile: UUID, trigger: Trigger) -> (any ExtractionAssistant)? {
        guard let s = try? store.settings(profile: profile), s.hasConsent else { return nil }
        if trigger == .automatic && s.scope != .everySlip { return nil }
        return factory(s)
    }
}
