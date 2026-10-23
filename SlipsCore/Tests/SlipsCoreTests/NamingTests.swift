import Foundation
import Testing
@testable import SlipsCore

@Suite struct NamingRuleTests {
    let id = UUID(uuidString: "ABCDEF12-3456-7890-ABCD-EF1234567890")!

    func slip(_ configure: (inout Slip) -> Void = { _ in }) -> Slip {
        var s = Slip(id: id, profileId: UUID(), status: .ready, capturedAt: Date(timeIntervalSince1970: 1_792_000_000),
                     pdfPath: "x", pdfSha256: String(repeating: "a", count: 64), pageCount: 1)
        s.merchant = "Quincaillerie Fictive"
        s.txnDate = CalendarDay(year: 2026, month: 10, day: 20)
        s.total = 4367
        s.kind = .enterprise
        configure(&s)
        return s
    }

    let labels = SlipLabels(business: "Studio Fictif", subcategoryKey: "enterprise.supplies", paymentMethod: "Visa pro")
    let localize: (String) -> String = { ["kind.enterprise": "Entreprise", "subcategory.enterprise.supplies": "Fournitures"][$0] ?? $0 }

    func path(_ rule: String, _ s: Slip? = nil) -> String {
        NamingRule(rule).path(for: s ?? slip(), labels: labels, localize: localize)
    }

    @Test func defaultRule() {
        #expect(path(NamingRule.defaultRule) == "Studio Fictif/2026/2026-10-20_Quincaillerie Fictive_43.67.pdf")
    }

    @Test func everyToken() {
        #expect(path("{year}") == "2026.pdf")
        #expect(path("{month}") == "10.pdf")
        #expect(path("{day}") == "20.pdf")
        #expect(path("{date}") == "2026-10-20.pdf")
        #expect(path("{kind}") == "Entreprise.pdf")
        #expect(path("{business}") == "Studio Fictif.pdf")
        #expect(path("{subcategory}") == "Fournitures.pdf")
        #expect(path("{merchant}") == "Quincaillerie Fictive.pdf")
        #expect(path("{total}") == "43.67.pdf")
        #expect(path("{currency}") == "CAD.pdf")
        #expect(path("{payment}") == "Visa pro.pdf")
        #expect(path("{id8}") == "abcdef12.pdf")
        #expect(NamingRule("{year}/{bogus}").unknownTokens == ["bogus"])
        #expect(NamingRule(NamingRule.defaultRule).unknownTokens.isEmpty)
    }

    @Test func customSubcategoryNameWins() {
        let l = SlipLabels(subcategoryKey: "enterprise.supplies", subcategoryName: "Quincaillerie")
        #expect(NamingRule("{subcategory}").path(for: slip(), labels: l, localize: localize) == "Quincaillerie.pdf")
    }

    @Test func forbiddenCharactersReplaced() {
        let s = slip { $0.merchant = #"A/B:C\D*E?F"G<H>I|J"# }
        #expect(path("{merchant}", s) == "A-B-C-D-E-F-G-H-I-J.pdf")
        let tricky = slip { $0.merchant = "../../etc" }
        #expect(!path("{merchant}/{date}", tricky).contains(".."))
        #expect(!path("{merchant}/{date}", tricky).hasPrefix("/"))
    }

    @Test func nfc() {
        let decomposed = "Cafe\u{0301} Fictif"
        let p = path("{merchant}", slip { $0.merchant = decomposed })
        #expect(p == "Café Fictif.pdf")
        #expect(p.unicodeScalars.count == "Café Fictif.pdf".unicodeScalars.count)
    }

    @Test func lengthCapPerComponent() {
        let long = String(repeating: "x", count: 300)
        let p = path("{merchant}/{merchant}", slip { $0.merchant = long })
        let parts = p.split(separator: "/")
        #expect(parts.count == 2)
        #expect(parts.allSatisfy { $0.count <= NamingRule.maxComponentLength })
        #expect(p.hasSuffix(".pdf"))
    }

    @Test func emptyTokensDropFoldersAndSeparators() {
        let personal = slip { $0.kind = .personal }
        let noBusiness = NamingRule(NamingRule.defaultRule).path(for: personal, labels: SlipLabels(), localize: localize)
        #expect(noBusiness == "2026/2026-10-20_Quincaillerie Fictive_43.67.pdf")
        let noMerchant = path("{date}_{merchant}_{total}", slip { $0.merchant = nil })
        #expect(noMerchant == "2026-10-20_43.67.pdf")
        #expect(path("{merchant}", slip { $0.merchant = nil }) == "abcdef12.pdf")
    }

    @Test func missingDateUsesCaptureDay() {
        #expect(path("{date}", slip { $0.txnDate = nil }) == "2026-10-14.pdf")
    }

    @Test func collisionSuffix() {
        #expect(NamingRule.withIdSuffix("Studio/2026/a.pdf", slip: slip()) == "Studio/2026/a_abcdef12.pdf")
        #expect(NamingRule.withIdSuffix(String(repeating: "y", count: 120) + ".pdf", slip: slip()).count <= 120)
        #expect(NamingRule.sidecarPath(for: "a/b.pdf") == "a/b.json")
    }

    @Test func plainAmounts() {
        #expect(NamingRule.plainAmount(123_456, currency: "CAD") == "1234.56")
        #expect(NamingRule.plainAmount(5, currency: "CAD") == "0.05")
        #expect(NamingRule.plainAmount(-250, currency: "CAD") == "-2.50")
    }
}

@Suite struct DirectoryWriterTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    func item(sidecar: Bool = false, merchant: String = "Fake", previous: String? = nil, content: String = "%PDF one",
              rule: String = NamingRule.defaultRule, id: UUID = UUID()) throws -> DeliveryItem {
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let data = Data(content.utf8)
        let url = source.appendingPathComponent("\(id).pdf")
        try data.write(to: url)
        var s = Slip(id: id, profileId: UUID(), status: .ready, pdfPath: "x", pdfSha256: Hashing.sha256Hex(data), pageCount: 1)
        s.merchant = merchant
        s.txnDate = CalendarDay(year: 2026, month: 10, day: 20)
        s.total = 1000
        let d = Destination(profileId: s.profileId, type: .folder, name: "F", config: sidecar ? [Destination.sidecarKey: "1"] : [:],
                            namingRule: rule, enabled: true)
        return DeliveryItem(slip: s, destination: d, pdfURL: url, sha256: s.pdfSha256, byteCount: data.count,
                            previousRef: previous.map(RemoteRef.init), labels: SlipLabels(business: "Shop"))
    }

    @Test func deliverThenExists() throws {
        let w = DirectoryWriter(root: root)
        let i = try item()
        #expect(try w.exists(i) == nil)
        let ref = try w.deliver(i)
        #expect(ref.value == "Shop/2026/2026-10-20_Fake_10.00.pdf")
        #expect(try Data(contentsOf: root.appendingPathComponent(ref.value)) == Data("%PDF one".utf8))
        #expect(try w.exists(i) == ref)
        // Delivering again writes nothing new.
        #expect(try w.deliver(i) == ref)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Shop/2026").path).count == 1)
    }

    @Test func nameTakenByAnotherFileGetsTheId() throws {
        let w = DirectoryWriter(root: root)
        let first = try item(content: "%PDF first")
        let second = try item(content: "%PDF second")
        let a = try w.deliver(first)
        let b = try w.deliver(second)
        #expect(a != b)
        #expect(b.value.hasSuffix("_\(second.slip.id.uuidString.lowercased().prefix(8)).pdf"))
        #expect(try w.exists(second) == b)
        #expect(try w.exists(first) == a)
    }

    @Test func sidecarWrittenAndCheckedByExists() throws {
        let w = DirectoryWriter(root: root)
        var i = try item(sidecar: true)
        let ref = try w.deliver(i)
        let json = try Data(contentsOf: root.appendingPathComponent(NamingRule.sidecarPath(for: ref.value)))
        let sidecar = try JSONDecoder.sidecar.decode(Sidecar.self, from: json)
        #expect(sidecar.id == i.slip.id.uuidString.lowercased())
        #expect(sidecar.total == 1000)
        #expect(sidecar.business == "Shop")
        #expect(sidecar.schema == Sidecar.schema)
        // An edit that keeps the name: the PDF is there but the sidecar is stale.
        i.slip.notes = "edited"
        #expect(try w.exists(i) == nil)
        #expect(try w.deliver(i) == ref)
        #expect(try w.exists(i) == ref)
    }

    @Test func renamedAfterEditMovesTheCopy() throws {
        let w = DirectoryWriter(root: root)
        let id = UUID()
        let before = try item(sidecar: true, merchant: "Old", id: id)
        let old = try w.deliver(before)
        let after = try item(sidecar: true, merchant: "New", previous: old.value, id: id)
        let new = try w.deliver(after)
        #expect(new != old)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(old.value).path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(NamingRule.sidecarPath(for: old.value)).path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(new.value).path))
    }

    @Test func previousCopyThatChangedIsKept() throws {
        let w = DirectoryWriter(root: root)
        let id = UUID()
        let old = try w.deliver(try item(merchant: "Old", id: id))
        // Someone replaced the old file with something else: never delete it.
        try Data("not ours".utf8).write(to: root.appendingPathComponent(old.value))
        _ = try w.deliver(try item(merchant: "New", previous: old.value, id: id))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(old.value).path))
    }
}

@Suite struct DestinationStoreTests {
    @Test func validationAndBacklog() throws {
        let h = try OutboxHarness()
        let store = DestinationStore(database: h.db)
        try h.readySlip([])
        var nas = Destination(profileId: h.profile.id, type: .webdav, name: "  ", enabled: false)
        #expect(throws: DestinationError.blankName) { try store.save(nas) }
        nas.name = "NAS"
        nas.namingRule = "{year}/{oops}"
        #expect(throws: DestinationError.unknownTokens(["oops"])) { try store.save(nas) }
        nas.namingRule = ""
        try store.save(nas)
        #expect(try store.list(profile: h.profile.id).first { $0.id == nas.id }?.namingRule == Destination.defaultNamingRule)
        #expect(try h.db.writer.read { try Delivery.fetchCount($0) } == 0)
        try store.setEnabled(nas.id, true)
        #expect(try h.db.writer.read { try Delivery.fetchCount($0) } == 1)
        // Off and on again does not duplicate.
        try store.setEnabled(nas.id, false)
        try store.setEnabled(nas.id, true)
        #expect(try h.db.writer.read { try Delivery.fetchCount($0) } == 1)
    }

    @Test func libraryStaysOn() throws {
        let h = try OutboxHarness()
        let store = DestinationStore(database: h.db)
        let library = try #require(try store.list(profile: h.profile.id).first)
        #expect(library.type == .library)
        #expect(throws: DestinationError.libraryIsPermanent) { try store.setEnabled(library.id, false) }
        #expect(throws: DestinationError.libraryIsPermanent) { try store.remove(library.id) }
        var off = library
        off.enabled = false
        try store.save(off)
        #expect(try store.list(profile: h.profile.id).first?.enabled == true)
    }

    @Test func removeDropsOutboxRows() throws {
        let h = try OutboxHarness()
        let store = DestinationStore(database: h.db)
        let nas = try h.destination("NAS")
        try h.readySlip([nas])
        try store.remove(nas.id)
        #expect(try h.db.writer.read { try Delivery.fetchCount($0) } == 0)
        #expect(try h.db.writer.read { try Slip.fetchCount($0) } == 1)
    }
}
