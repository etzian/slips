import Foundation
import SlipsCore
import Testing
@testable import Slips

@MainActor
@Suite struct MandatoryTests {
    @Test func firstRunFlag() {
        let defaults = UserDefaults(suiteName: "first-run-\(UUID())")!
        let state = FirstRunState(defaults: defaults)
        #expect(!state.isDone)
        state.markDone()
        #expect(state.isDone)
        state.reset()
        #expect(!state.isDone)
    }

    @Test func eraseLeavesNoFileOrRowAndStartsOver() throws {
        let defaults = UserDefaults(suiteName: "erase-\(UUID())")!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(database: try AppDatabase.inMemory(), files: FileStore(root: root), defaults: defaults)
        model.firstRunDone = true
        let profile = try #require(model.activeProfileId)
        let slip = try model.capture.save(pdf: Data("%PDF".utf8), pageCount: 1, profile: profile)
        try model.eraseAll()
        #expect(!FileManager.default.fileExists(atPath: model.files.url(for: slip.pdfPath).path))
        #expect(try model.slips.slip(slip.id) == nil)
        #expect(try model.database.profiles().count == 1)
        #expect(model.activeProfileId != profile)
        #expect(!model.firstRunDone)
    }

    @Test func slipFilesAreProtected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = FileStore(root: root)
        let path = try store.writePDF(Data("%PDF".utf8), profile: UUID(), slip: UUID())
        let attributes = try FileManager.default.attributesOfItem(atPath: store.url(for: path).path)
        // The simulator may not report a class; a device must report complete protection.
        if let protection = attributes[.protectionKey] as? FileProtectionType {
            #expect(protection == .complete)
        }
    }

    @Test func companyFactsAreGenerated() {
        #expect(!Company.legalName.isEmpty)
        #expect(Company.copyrightTemplate.contains("{year}"))
        #expect(!AppInfo.copyright.contains("{year}"))
    }
}
