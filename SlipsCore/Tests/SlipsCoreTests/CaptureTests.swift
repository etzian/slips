import Foundation
import GRDB
import Testing
@testable import SlipsCore

@Suite struct HashingTests {
    @Test func standardVectors() {
        #expect(Hashing.sha256Hex(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(Hashing.sha256Hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(Hashing.sha256Hex(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8))
            == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        #expect(Hashing.sha256Hex(Data(repeating: 0x61, count: 1_000_000))
            == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }
}

@Suite struct CaptureStoreTests {
    let db: AppDatabase
    let files: FileStore
    let store: CaptureStore
    let profile: Profile

    init() throws {
        db = try AppDatabase.inMemory()
        files = FileStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        store = CaptureStore(database: db, files: files)
        profile = try db.createProfile(name: "P")
    }

    @Test func saveWritesFileThenDraftRow() throws {
        let pdf = Data("%PDF synthetic two pages".utf8)
        let slip = try store.save(pdf: pdf, pageCount: 2, profile: profile.id)
        #expect(try files.read(slip.pdfPath) == pdf)
        let row = try #require(try db.writer.read { try Slip.fetchOne($0, id: slip.id) })
        #expect(row.status == .draft)
        #expect(row.pageCount == 2)
        #expect(row.pdfSha256 == Hashing.sha256Hex(pdf))
        #expect(row.pdfPath == FileStore.pdfPath(profile: profile.id, slip: slip.id))
    }

    @Test func failedInsertLeavesNoFile() throws {
        #expect(throws: DatabaseError.self) {
            try store.save(pdf: Data("x".utf8), pageCount: 0, profile: profile.id)
        }
        #expect(try files.slipFolders().isEmpty)
    }

    @Test func sweepRemovesOrphansAndFlagsMissingFiles() throws {
        let kept = try store.save(pdf: Data("a".utf8), pageCount: 1, profile: profile.id)
        let lost = try store.save(pdf: Data("b".utf8), pageCount: 1, profile: profile.id)
        // A capture killed between file and row.
        let orphan = UUID()
        try files.writePDF(Data("c".utf8), profile: profile.id, slip: orphan)
        // A row whose file disappeared.
        try FileManager.default.removeItem(at: files.url(for: lost.pdfPath))

        let report = try store.sweep()
        #expect(report == .init(orphanFoldersRemoved: 1, rowsMissingFile: 1))
        #expect(!files.exists(FileStore.pdfPath(profile: profile.id, slip: orphan)))
        #expect(files.exists(kept.pdfPath))
        let flagged = try #require(try db.writer.read { try Slip.fetchOne($0, id: lost.id) })
        #expect(flagged.decodedChecks == [.fileMissing])
        let fine = try #require(try db.writer.read { try Slip.fetchOne($0, id: kept.id) })
        #expect(fine.decodedChecks.isEmpty)
        // Idempotent.
        #expect(try store.sweep() == .init(orphanFoldersRemoved: 0, rowsMissingFile: 0))
    }

    @Test func replacePDFUpdatesHashUntilDelivered() throws {
        let slip = try store.save(pdf: Data("v1".utf8), pageCount: 1, profile: profile.id)
        try store.replacePDF(of: slip.id, with: Data("v2 with text".utf8))
        let row = try #require(try db.writer.read { try Slip.fetchOne($0, id: slip.id) })
        #expect(row.pdfSha256 == Hashing.sha256Hex(Data("v2 with text".utf8)))
        #expect(try files.read(row.pdfPath) == Data("v2 with text".utf8))
        try db.writer.write { db in
            let dest = try Destination.fetchOne(db)!
            try Delivery(slipId: slip.id, destinationId: dest.id).insert(db)
        }
        #expect(throws: CaptureError.pdfImmutable) { try store.replacePDF(of: slip.id, with: Data("v3".utf8)) }
        #expect(try files.read(row.pdfPath) == Data("v2 with text".utf8))
    }
}
