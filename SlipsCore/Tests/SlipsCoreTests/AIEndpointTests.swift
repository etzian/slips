import Foundation
import GRDB
import Testing
@testable import SlipsCore

/// Counts what would have been sent.
final class SpyAssistant: ExtractionAssistant, @unchecked Sendable {
    // @unchecked: `inputs` is guarded by `lock`.
    let id = "spy"
    private let lock = NSLock()
    private var _inputs: [AssistantInput] = []
    var inputs: [AssistantInput] { lock.withLock { _inputs } }

    func extract(_ input: AssistantInput) async throws -> AIExtraction {
        lock.withLock { _inputs.append(input) }
        return AIExtraction()
    }
}

@Suite struct AIEndpointTests {
    let db: AppDatabase
    let store: AIEndpointStore
    let profile: Profile
    let spy = SpyAssistant()
    var router: AssistantRouter { AssistantRouter(store: store, factory: { [spy] _ in spy }) }

    init() throws {
        db = try AppDatabase.inMemory()
        store = AIEndpointStore(database: db)
        profile = try db.createProfile(name: "P")
    }

    @Test func offByDefaultNothingIsSent() throws {
        #expect(try store.settings(profile: profile.id).provider == .off)
        #expect(router.endpoint(profile: profile.id, trigger: .userRequest) == nil)
        #expect(router.endpoint(profile: profile.id, trigger: .automatic) == nil)
    }

    @Test func providerWithoutConsentSendsNothing() throws {
        try store.save(AIEndpointSettings(profileId: profile.id, provider: .claude, scope: .everySlip))
        #expect(router.endpoint(profile: profile.id, trigger: .userRequest) == nil)
        #expect(router.endpoint(profile: profile.id, trigger: .automatic) == nil)
        #expect(throws: ValidationError.notFound) { try store.consent(profile: UUID()) }
    }

    @Test func consentAndScope() async throws {
        try store.save(AIEndpointSettings(profileId: profile.id, provider: .ollama, baseUrl: "http://nas.local:11434",
                                          localNetwork: true, scope: .onRequest))
        try store.consent(profile: profile.id)
        #expect(try store.settings(profile: profile.id).hasConsent)
        // On request: only when the user asks.
        #expect(router.endpoint(profile: profile.id, trigger: .automatic) == nil)
        let asked = try #require(router.endpoint(profile: profile.id, trigger: .userRequest))
        _ = try await asked.extract(AssistantInput(ocrText: "x", localeIdentifier: "fr_CA"))
        #expect(spy.inputs.count == 1)
    }

    @Test func changingProviderOrScopeAsksAgain() throws {
        try store.save(AIEndpointSettings(profileId: profile.id, provider: .claude, scope: .onRequest))
        try store.consent(profile: profile.id)
        var s = try store.settings(profile: profile.id)
        s.scope = .everySlip
        try store.save(s)
        #expect(!(try store.settings(profile: profile.id).hasConsent))
        #expect(router.endpoint(profile: profile.id, trigger: .automatic) == nil)
        try store.consent(profile: profile.id)
        #expect(router.endpoint(profile: profile.id, trigger: .automatic) != nil)
        s = try store.settings(profile: profile.id)
        s.provider = .openai
        try store.save(s)
        #expect(router.endpoint(profile: profile.id, trigger: .userRequest) == nil)
        // Same provider and scope saved again (e.g. a new model name): consent holds.
        try store.consent(profile: profile.id)
        s = try store.settings(profile: profile.id)
        s.model = "another-model"
        try store.save(s)
        #expect(try store.settings(profile: profile.id).hasConsent)
    }

    @Test func olderConsentVersionAsksAgain() throws {
        try store.save(AIEndpointSettings(profileId: profile.id, provider: .claude))
        try store.consent(profile: profile.id)
        try db.writer.write { db in try db.execute(sql: "UPDATE ai_endpoints SET consent_version = 0") }
        #expect(!(try store.settings(profile: profile.id).hasConsent))
        #expect(router.endpoint(profile: profile.id, trigger: .userRequest) == nil)
    }

    @Test func withdrawStopsEverything() throws {
        try store.save(AIEndpointSettings(profileId: profile.id, provider: .openai, scope: .everySlip))
        try store.consent(profile: profile.id)
        try store.withdraw(profile: profile.id)
        let s = try store.settings(profile: profile.id)
        #expect(s.provider == .off && s.consentAt == nil)
        #expect(router.endpoint(profile: profile.id, trigger: .userRequest) == nil)
    }

    @Test func providerValuesAreChecked() {
        #expect(throws: DatabaseError.self) {
            try db.writer.write { db in
                try db.execute(sql: "INSERT INTO ai_endpoints (profile_id, provider, updated_at) VALUES (?, 'gemini', '2026-10-24')",
                               arguments: [profile.id])
            }
        }
    }
}

@Suite struct AIPrivacyTests {
    /// Made-up digit runs, built at run time so no card-like number sits in the sources.
    static func run(_ groups: [String], _ sep: String) -> String { groups.joined(separator: sep) }
    static let dots12 = String(repeating: "•", count: 12)

    @Test func longDigitRunsKeepTheirLastFour() {
        let card = Self.run(["0000", "0000", "0000", "1234"], " ")
        #expect(AIPrivacy.mask("Card \(card) OK") == "Card \(Self.dots12)1234 OK")
        let loyalty = Self.run(["0000", "0000", "0000", "9012"], "-")
        #expect(AIPrivacy.mask("PC Optimum \(loyalty)") == "PC Optimum \(Self.dots12)9012")
        let aid = "A" + String(repeating: "0", count: 9) + "1010"
        #expect(AIPrivacy.mask(aid) == "A" + String(repeating: "•", count: 9) + "1010")
    }

    @Test func registrationNumbersAmountsAndMasksStay() {
        let text = "TPS 123456789 RT0001\nTVQ 1234567890 TQ0001\nTOTAL 1 234,56\n************0029\nTel 418 555 0100"
        #expect(AIPrivacy.mask(text) == text)
    }

    @Test func inputCarriesOnlyTheMaskedText() {
        var slip = Slip(profileId: UUID(), pdfPath: "x", pdfSha256: String(repeating: "a", count: 64), pageCount: 1)
        #expect(AIPrivacy.input(for: slip, locale: "fr_CA") == nil)
        slip.ocrText = "VISA " + String(repeating: "0", count: 12) + "1234\nTOTAL 11,50"
        slip.notes = "private note"
        let input = AIPrivacy.input(for: slip, locale: "fr_CA")
        #expect(input?.ocrText == "VISA \(AIPrivacyTests.dots12)1234\nTOTAL 11,50")
        #expect(input?.ocrText.contains("private") == false)
    }
}
