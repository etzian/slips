import Foundation
import GRDB

/// Saves a capture: the PDF on disk first, then its `slips` row, before the UI moves on. Capture never
/// waits on the network.
public struct CaptureStore: Sendable {
    public let database: AppDatabase
    public let files: FileStore

    public init(database: AppDatabase, files: FileStore) {
        self.database = database
        self.files = files
    }

    /// Writes `pdf` for a new slip and inserts its draft row. If the app dies between the two, the
    /// startup sweep removes the file.
    @discardableResult
    public func save(pdf: Data, pageCount: Int, profile: UUID, currency: String = "CAD", now: Date = Date()) throws -> Slip {
        let id = UUID()
        let path = try files.writePDF(pdf, profile: profile, slip: id)
        let slip = Slip(id: id, profileId: profile, status: .draft, capturedAt: now, pdfPath: path,
                        pdfSha256: Hashing.sha256Hex(pdf), pageCount: pageCount, currency: currency)
        do {
            try database.writer.write { db in try slip.insert(db) }
        } catch {
            try? files.removeSlip(profile: profile, slip: id)
            throw error
        }
        return slip
    }

    /// Replaces a draft's PDF (the same pages with an OCR text layer) and its hash. Refused once the
    /// slip has deliveries: a delivered PDF is immutable.
    public func replacePDF(of slipId: UUID, with pdf: Data) throws {
        try database.writer.write { db in
            guard var slip = try Slip.fetchOne(db, id: slipId) else { throw ValidationError.notFound }
            let deliveries = try Delivery.filter(Column("slip_id") == slipId).fetchCount(db)
            guard deliveries == 0 else { throw CaptureError.pdfImmutable }
            try files.write(pdf, to: slip.pdfPath, protection: .complete)
            slip.pdfSha256 = Hashing.sha256Hex(pdf)
            slip.updatedAt = Date()
            try slip.update(db)
        }
    }

    /// Stores the parser's output on a slip: the raw extraction, the OCR text and the fields it filled.
    /// Values the user already typed are kept.
    public func recordExtraction(_ extraction: Extraction, ocrText: String, for slipId: UUID) throws {
        try database.writer.write { db in
            guard var slip = try Slip.fetchOne(db, id: slipId) else { throw ValidationError.notFound }
            let edited = slip.extracted != nil
            if edited {
                slip.ocrText = ocrText
                slip.extracted = extraction.json
            } else {
                slip.apply(extraction, ocrText: ocrText)
            }
            slip.updatedAt = Date()
            try slip.update(db)
        }
    }

    public struct SweepReport: Equatable, Sendable {
        public var orphanFoldersRemoved: Int
        public var rowsMissingFile: Int
    }

    /// Run at launch, before capture is offered: removes slip folders with no row (a capture killed
    /// between file and row) and flags rows whose PDF is gone with the blocking `file_missing` check.
    @discardableResult
    public func sweep() throws -> SweepReport {
        var report = SweepReport(orphanFoldersRemoved: 0, rowsMissingFile: 0)
        let rows = try database.writer.read { db in try Slip.fetchAll(db) }
        let known = Set(rows.map(\.id))
        for folder in try files.slipFolders() where !known.contains(folder.slip) {
            try files.removeSlip(profile: folder.profile, slip: folder.slip)
            report.orphanFoldersRemoved += 1
        }
        try database.writer.write { db in
            for var slip in rows where !files.exists(slip.pdfPath) {
                var checks = slip.decodedChecks
                guard !checks.contains(where: { $0.code == Check.fileMissing.code }) else { continue }
                checks.append(.fileMissing)
                slip.setChecks(checks)
                try slip.update(db)
                report.rowsMissingFile += 1
            }
        }
        return report
    }
}

public enum CaptureError: Error, Equatable, Sendable {
    case pdfImmutable
    case noPages
}
