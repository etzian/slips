import Foundation
import GRDB
import Testing
@testable import SlipsCore

@Suite struct ReferenceDataTests {
    let db: AppDatabase
    let ref: ReferenceData
    let profile: Profile

    init() throws {
        db = try AppDatabase.inMemory()
        ref = ReferenceData(database: db)
        profile = try ref.createProfile(name: "Home")
    }

    private func slip(_ configure: (inout Slip) -> Void) throws {
        var s = Slip(profileId: profile.id, pdfPath: "x", pdfSha256: String(repeating: "e", count: 64), pageCount: 1)
        configure(&s)
        try db.writer.write { [s] db in try s.insert(db) }
    }

    @Test func blankNamesRefused() throws {
        #expect(throws: ValidationError.blankName) { try ref.createProfile(name: "  ") }
        #expect(throws: ValidationError.blankName) { try ref.renameProfile(profile.id, to: "\n") }
        #expect(throws: ValidationError.blankName) { try ref.addEnterprise(profile: profile.id, name: "") }
        #expect(throws: ValidationError.blankName) { try ref.addSubcategory(profile: profile.id, kind: .personal, name: " ") }
        #expect(throws: ValidationError.blankName) {
            try ref.savePaymentMethod(PaymentMethod(profileId: profile.id, name: " ", type: .cash))
        }
    }

    @Test func renameProfile() throws {
        try ref.renameProfile(profile.id, to: " Family ")
        #expect(try db.profiles().first?.name == "Family")
    }

    @Test func lastFourMustBeExactlyFourDigits() throws {
        for bad in ["123", "12345", "12a4", "١٢٣٤"] {
            #expect(throws: ValidationError.invalidLastFour) {
                try ref.savePaymentMethod(PaymentMethod(profileId: profile.id, name: "Visa", type: .creditCard, last4: bad))
            }
        }
        try ref.savePaymentMethod(PaymentMethod(profileId: profile.id, name: "Visa", type: .creditCard, last4: "0042"))
        try ref.savePaymentMethod(PaymentMethod(profileId: profile.id, name: "Cash", type: .cash, last4: " "))
        let methods = try ref.snapshot(profile: profile.id).paymentMethods
        #expect(methods.map(\.last4) == [nil, "0042"]) // ordered by name: Cash, Visa
    }

    @Test func currencyValidatedAndUppercased() throws {
        #expect(throws: ValidationError.invalidCurrency) {
            try ref.savePaymentMethod(PaymentMethod(profileId: profile.id, name: "Card", type: .debit, currency: "CA"))
        }
        try ref.savePaymentMethod(PaymentMethod(profileId: profile.id, name: "Card", type: .debit, currency: "usd"))
        #expect(try ref.snapshot(profile: profile.id).paymentMethods.first?.currency == "USD")
    }

    @Test func defaultBusinessOnlyForEnterpriseKind() throws {
        let e = try ref.addEnterprise(profile: profile.id, name: "Shop")
        let m = PaymentMethod(profileId: profile.id, name: "Card", type: .creditCard, defaultKind: .personal, defaultEnterpriseId: e.id)
        try ref.savePaymentMethod(m)
        #expect(try ref.snapshot(profile: profile.id).paymentMethods.first?.defaultEnterpriseId == nil)
    }

    @Test func transferKeysCannotBeArchived() throws {
        let subs = try ref.snapshot(profile: profile.id).subcategories
        for key in ["any.transfer", "any.card_payment"] {
            let s = try #require(subs.first { $0.nameKey == key })
            #expect(throws: ValidationError.archiveRefused) { try ref.removeSubcategory(s.id) }
        }
        #expect(try ref.snapshot(profile: profile.id).subcategories.count == 27)
    }

    @Test func seededSubcategoryIsArchivedNotDeleted() throws {
        let s = try #require(try ref.snapshot(profile: profile.id).subcategories.first { $0.nameKey == "personal.leisure" })
        #expect(try ref.removeSubcategory(s.id) == .archived)
        #expect(try ref.snapshot(profile: profile.id).subcategories.count == 26)
        try ref.unarchiveSubcategory(s.id)
        #expect(try ref.snapshot(profile: profile.id).subcategories.count == 27)
    }

    @Test func customSubcategoryDeletedWhenUnusedArchivedWhenUsed() throws {
        let unused = try ref.addSubcategory(profile: profile.id, kind: .personal, name: "Books")
        #expect(unused.sortOrder == 27)
        #expect(try ref.removeSubcategory(unused.id) == .deleted)
        let used = try ref.addSubcategory(profile: profile.id, kind: .personal, name: "Garden")
        try slip { $0.subcategoryId = used.id }
        #expect(try ref.removeSubcategory(used.id) == .archived)
        #expect(try db.writer.read { try Subcategory.fetchOne($0, id: used.id) }?.archivedAt != nil)
    }

    @Test func renamingSeededSubcategoryAndResettingIt() throws {
        let s = try #require(try ref.snapshot(profile: profile.id).subcategories.first)
        try ref.renameSubcategory(s.id, to: "Food")
        #expect(try ref.snapshot(profile: profile.id).subcategories.first?.customName == "Food")
        try ref.renameSubcategory(s.id, to: "")
        #expect(try ref.snapshot(profile: profile.id).subcategories.first?.customName == nil)
        let custom = try ref.addSubcategory(profile: profile.id, kind: .family, name: "Pets")
        #expect(throws: ValidationError.blankName) { try ref.renameSubcategory(custom.id, to: " ") }
    }

    @Test func enterpriseRemoval() throws {
        let a = try ref.addEnterprise(profile: profile.id, name: "A")
        #expect(try ref.removeEnterprise(a.id) == .deleted)
        let b = try ref.addEnterprise(profile: profile.id, name: "B")
        try slip { $0.kind = .enterprise; $0.enterpriseId = b.id }
        #expect(try ref.removeEnterprise(b.id) == .archived)
        #expect(try ref.snapshot(profile: profile.id).enterprises.isEmpty)
        try ref.unarchiveEnterprise(b.id)
        #expect(try ref.snapshot(profile: profile.id).enterprises.map(\.name) == ["B"])
        try ref.renameEnterprise(b.id, to: "B Inc.")
        #expect(try ref.snapshot(profile: profile.id).enterprises.map(\.name) == ["B Inc."])
    }

    @Test func paymentMethodRemoval() throws {
        let m = PaymentMethod(profileId: profile.id, name: "Visa", type: .creditCard, last4: "0001")
        try ref.savePaymentMethod(m)
        try slip { $0.paymentMethodId = m.id }
        #expect(try ref.removePaymentMethod(m.id) == .archived)
        let n = PaymentMethod(profileId: profile.id, name: "Cash", type: .cash)
        try ref.savePaymentMethod(n)
        #expect(try ref.removePaymentMethod(n.id) == .deleted)
    }

    @Test func subcategoriesForKindIncludeAny() throws {
        let snap = try ref.snapshot(profile: profile.id)
        let keys = snap.subcategories(for: .enterprise).compactMap(\.nameKey)
        #expect(keys.contains("enterprise.software"))
        #expect(keys.contains("any.transfer"))
        #expect(!keys.contains("personal.groceries"))
    }

    @Test func observationEmitsAfterChange() async throws {
        var iterator = ref.observeEnterprises(profile: profile.id).makeAsyncIterator()
        #expect(try await iterator.next()?.isEmpty == true)
        try ref.addEnterprise(profile: profile.id, name: "Studio")
        #expect(try await iterator.next()?.map(\.name) == ["Studio"])
    }
}
