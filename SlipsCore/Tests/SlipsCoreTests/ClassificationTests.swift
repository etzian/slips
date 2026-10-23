import Foundation
import GRDB
import Testing
@testable import SlipsCore

@Suite struct MerchantNameTests {
    @Test func normalisation() {
        #expect(MerchantName.normalize("ÉPICERIE FICTIVE #0042") == "epicerie fictive")
        #expect(MerchantName.normalize("Epicerie Fictive inc.") == "epicerie fictive")
        #expect(MerchantName.normalize("Café  Fictif — succ. 12") == "cafe fictif")
        #expect(MerchantName.normalize("FAKE HARDWARE STORE 0001") == "fake hardware")
        #expect(MerchantName.normalize("Quincaillerie Fictive Ltée") == "quincaillerie fictive")
        #expect(MerchantName.normalize("1234") == "")
    }
}

@Suite struct SuggestionTests {
    let profile = UUID()
    let shop = UUID(), studio = UUID()
    let groceries = UUID(), software = UUID(), transfer = UUID(), dining = UUID()
    let visa = UUID(), debit = UUID()

    var reference: ReferenceSnapshot {
        ReferenceSnapshot(
            enterprises: [Enterprise(id: shop, profileId: profile, name: "Shop"), Enterprise(id: studio, profileId: profile, name: "Studio")],
            subcategories: [
                Subcategory(id: groceries, profileId: profile, kind: .personal, nameKey: "personal.groceries"),
                Subcategory(id: dining, profileId: profile, kind: .personal, nameKey: "personal.dining"),
                Subcategory(id: software, profileId: profile, kind: .enterprise, nameKey: "enterprise.software"),
                Subcategory(id: transfer, profileId: profile, kind: .any, nameKey: "any.transfer"),
            ],
            paymentMethods: [
                PaymentMethod(id: visa, profileId: profile, name: "Visa", type: .creditCard, last4: "0042",
                              defaultKind: .enterprise, defaultEnterpriseId: studio),
                PaymentMethod(id: debit, profileId: profile, name: "Debit", type: .debit, last4: "0007", defaultKind: .personal),
            ])
    }

    func memory(_ kind: Kind?, enterprise: UUID? = nil, sub: UUID? = nil, method: UUID? = nil) -> MerchantMemory {
        MerchantMemory(profileId: profile, merchantNorm: "x", kind: kind, enterpriseId: enterprise, subcategoryId: sub, paymentMethodId: method)
    }

    @Test func cardDefaultsWinOverMemory() {
        let c = Suggestions.suggest(cardLast4: "0042", merchant: "Fake", reference: reference,
                                    memory: memory(.personal, sub: groceries, method: debit), lastUsed: nil)
        #expect(c.paymentMethodId == visa)
        #expect(c.kind == .enterprise)
        #expect(c.enterpriseId == studio)
        // The memory's personal sub-category does not fit an enterprise slip.
        #expect(c.subcategoryId == nil)
    }

    @Test func memoryFillsWhatTheCardLeaves() {
        let c = Suggestions.suggest(cardLast4: "0042", merchant: "Fake", reference: reference,
                                    memory: memory(.enterprise, enterprise: shop, sub: software), lastUsed: nil)
        #expect(c.enterpriseId == studio)
        #expect(c.subcategoryId == software)
    }

    @Test func memoryWithoutCard() {
        let c = Suggestions.suggest(cardLast4: nil, merchant: "Fake", reference: reference,
                                    memory: memory(.personal, sub: dining, method: debit), lastUsed: memory(.enterprise, enterprise: shop))
        #expect(c == Classification(kind: .personal, subcategoryId: dining, paymentMethodId: debit))
    }

    @Test func lastUsedIsTheLastResort() {
        let c = Suggestions.suggest(cardLast4: "9999", merchant: nil, reference: reference, memory: nil,
                                    lastUsed: memory(.enterprise, enterprise: shop, sub: transfer, method: visa))
        #expect(c == Classification(kind: .enterprise, enterpriseId: shop, subcategoryId: transfer, paymentMethodId: visa))
    }

    @Test func archivedValuesAreNotSuggested() {
        let gone = UUID()
        let c = Suggestions.suggest(cardLast4: nil, merchant: "Fake", reference: reference,
                                    memory: memory(.enterprise, enterprise: gone, sub: gone, method: gone), lastUsed: nil)
        #expect(c == Classification(kind: .enterprise))
    }

    @Test func nothingKnown() {
        #expect(Suggestions.suggest(cardLast4: nil, merchant: nil, reference: reference, memory: nil, lastUsed: nil) == Classification())
    }
}

@Suite struct SlipStoreTests {
    let db: AppDatabase
    let store: SlipStore
    let profile: Profile
    let snapshot: ReferenceSnapshot

    init() throws {
        db = try AppDatabase.inMemory()
        let files = FileStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try files.write(Data("pdf".utf8), to: "x")
        store = SlipStore(database: db, files: files)
        profile = try db.createProfile(name: "P")
        snapshot = try ReferenceData(database: db).snapshot(profile: profile.id)
    }

    func draft(merchant: String = "Épicerie Fictive #12") throws -> Slip {
        var s = Slip(profileId: profile.id, pdfPath: "x", pdfSha256: String(repeating: "a", count: 64), pageCount: 1)
        s.merchant = merchant
        s.total = 1000
        try db.writer.write { [s] db in try s.insert(db) }
        return s
    }

    var groceries: UUID { snapshot.subcategories.first { $0.nameKey == "personal.groceries" }!.id }

    @Test func draftGetsNoDelivery() throws {
        var s = try draft()
        s.notes = "kept"
        try store.saveDraft(s)
        #expect(try store.slip(s.id)?.notes == "kept")
        #expect(try store.slip(s.id)?.status == .draft)
        #expect(try db.writer.read { try Delivery.fetchCount($0) } == 0)
    }

    @Test func readyCreatesDeliveriesForEnabledDestinationsOnly() throws {
        try db.writer.write { db in
            try db.execute(sql: "UPDATE destinations SET enabled = 1 WHERE type = 'icloud'")
            try Destination(profileId: profile.id, type: .webdav, name: "NAS", enabled: false).insert(db)
        }
        var s = try draft()
        s.kind = .personal
        s.subcategoryId = groceries
        try store.markReady(s)
        let deliveries = try db.writer.read { try Delivery.fetchAll($0) }
        #expect(deliveries.count == 1)
        #expect(deliveries.first?.status == .pending)
        #expect(try store.slip(s.id)?.status == .ready)
        // Saving again does not duplicate.
        try store.markReady(s)
        #expect(try db.writer.read { try Delivery.fetchCount($0) } == 1)
    }

    @Test func readyUpdatesMerchantMemoryAndSuggestsNextTime() throws {
        var s = try draft()
        s.kind = .personal
        s.subcategoryId = groceries
        try store.markReady(s)
        try store.markReady(s)
        let memory = try db.writer.read { try MerchantMemory.fetchOne($0) }
        #expect(memory?.merchantNorm == "epicerie fictive")
        #expect(memory?.uses == 2)
        let next = try draft(merchant: "EPICERIE FICTIVE #99")
        #expect(try store.suggestion(for: next) == Classification(kind: .personal, subcategoryId: groceries))
    }

    @Test func readyRefusedWhenIncompleteOrBlocked() throws {
        var s = try draft()
        #expect(throws: SaveError.classificationIncomplete) { try store.markReady(s) }
        s.kind = .enterprise
        s.subcategoryId = groceries
        #expect(throws: SaveError.classificationIncomplete) { try store.markReady(s) }
        s.kind = .personal
        s.total = nil
        #expect(throws: SaveError.blockingCheck("total_missing")) { try store.markReady(s) }
        #expect(try store.slip(s.id)?.status == .draft)
    }

    @Test func businessClearedForNonBusinessKind() throws {
        let shop = try ReferenceData(database: db).addEnterprise(profile: profile.id, name: "Shop")
        var s = try draft()
        s.kind = .personal
        s.enterpriseId = shop.id
        s.subcategoryId = groceries
        try store.markReady(s)
        #expect(try store.slip(s.id)?.enterpriseId == nil)
    }
}
