import Foundation
import GRDB
import Testing
@testable import SlipsCore

/// A destination whose answers are scripted. It keeps what it received, so a test can count copies.
final class FakeDestination: DestinationAdapter, @unchecked Sendable {
    // @unchecked: every mutable field is guarded by `lock`.
    enum Step {
        case ok
        /// The write succeeded but the answer was lost.
        case writeThenTimeout
        case fail(DeliveryError)
        case slow(UInt64)
    }

    private let lock = NSLock()
    private var _reachability: Reachability = .reachable
    private var _script: [Step] = []
    private var _stored: [UUID: String] = [:]
    private var _writes = 0
    private var _active = 0
    private var _maxActive = 0
    let name: String
    let tracker: ConcurrencyTracker?

    init(name: String = "fake", tracker: ConcurrencyTracker? = nil) {
        self.name = name
        self.tracker = tracker
    }

    var reachability: Reachability {
        get { lock.withLock { _reachability } }
        set { lock.withLock { _reachability = newValue } }
    }
    func script(_ steps: Step...) { lock.withLock { _script.append(contentsOf: steps) } }
    var writes: Int { lock.withLock { _writes } }
    var stored: [UUID: String] { lock.withLock { _stored } }
    var maxActive: Int { lock.withLock { _maxActive } }

    func probe() async -> Reachability { reachability }

    func exists(_ item: DeliveryItem) async throws -> RemoteRef? {
        lock.withLock { _stored[item.slip.id] == item.sha256 } ? RemoteRef("\(name)/\(item.slip.id)") : nil
    }

    func deliver(_ item: DeliveryItem) async throws -> RemoteRef {
        let step: Step = lock.withLock {
            _active += 1
            _maxActive = max(_maxActive, _active)
            return _script.isEmpty ? .ok : _script.removeFirst()
        }
        await tracker?.enter()
        defer { lock.withLock { _active -= 1 } }
        func write() { lock.withLock { _stored[item.slip.id] = item.sha256; _writes += 1 } }
        switch step {
        case .ok:
            write()
        case .slow(let ns):
            try? await Task.sleep(nanoseconds: ns)
            write()
        case .writeThenTimeout:
            write()
            await tracker?.leave()
            throw DeliveryError.transient("timeout")
        case .fail(let e):
            await tracker?.leave()
            throw e
        }
        await tracker?.leave()
        return RemoteRef("\(name)/\(item.slip.id)")
    }
}

actor ConcurrencyTracker {
    private(set) var active = 0
    private(set) var maxActive = 0
    func enter() { active += 1; maxActive = max(maxActive, active) }
    func leave() { active -= 1 }
}

final class TestClock: @unchecked Sendable {
    // @unchecked: `date` is guarded by `lock`.
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date = date.addingTimeInterval(seconds) } }
}

struct OutboxHarness {
    let db: AppDatabase
    let files: FileStore
    let profile: Profile
    let clock = TestClock()
    let queue: DeliveryQueue

    init() throws {
        db = try AppDatabase.inMemory()
        files = FileStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        profile = try db.createProfile(name: "P")
        queue = DeliveryQueue(database: db)
    }

    func destination(_ name: String, type: DestinationType = .webdav, wifiOnly: Bool = false, config: [String: String] = [:]) throws -> Destination {
        let d = Destination(profileId: profile.id, type: type, name: name, config: config, wifiOnly: wifiOnly, enabled: true)
        try db.writer.write { try d.insert($0) }
        return d
    }

    /// A ready slip with a real file, queued to `destinations`.
    @discardableResult
    func readySlip(_ destinations: [Destination], merchant: String = "Fake") throws -> Slip {
        let id = UUID()
        let pdf = Data("%PDF synthetic \(id)".utf8)
        let path = try files.writePDF(pdf, profile: profile.id, slip: id)
        var s = Slip(id: id, profileId: profile.id, status: .ready, capturedAt: clock.now, pdfPath: path,
                     pdfSha256: Hashing.sha256Hex(pdf), pageCount: 1)
        s.merchant = merchant
        s.total = 1000
        let slip = s
        try db.writer.write { db in
            try slip.insert(db)
            for d in destinations {
                try Delivery(slipId: slip.id, destinationId: d.id, nextAttemptAt: clock.now, updatedAt: clock.now).insert(db)
            }
        }
        return slip
    }

    func outbox(_ adapters: [UUID: FakeDestination], network: NetworkConditions = .unrestricted) -> Outbox {
        let clock = self.clock
        return Outbox(database: db, files: files, adapters: { adapters[$0.id] }, network: { network }, now: { clock.now })
    }

    func delivery(_ slip: Slip, _ d: Destination) throws -> Delivery {
        try db.writer.read { db in try Delivery.fetchOne(db, key: ["slip_id": slip.id, "destination_id": d.id])! }
    }
}

@Suite struct OutboxTests {
    @Test func offlineThenOnline() async throws {
        let h = try OutboxHarness()
        let nas = try h.destination("NAS")
        let fake = FakeDestination()
        let slip = try h.readySlip([nas])
        let outbox = h.outbox([nas.id: fake])

        fake.reachability = .unreachable
        var report = await outbox.drain()
        #expect(report.skippedDestinations == 1)
        #expect(try h.delivery(slip, nas).status == .pending)
        #expect(try h.delivery(slip, nas).attempts == 0)

        fake.reachability = .reachable
        report = await outbox.drain()
        #expect(report.delivered == 1)
        let row = try h.delivery(slip, nas)
        #expect(row.status == .done)
        #expect(row.remoteRef == "fake/\(slip.id)")
        #expect(row.deliveredSha256 == slip.pdfSha256)
        #expect(fake.writes == 1)
    }

    @Test func serverErrorThenSuccessFollowsBackoff() async throws {
        let h = try OutboxHarness()
        let nas = try h.destination("NAS")
        let fake = FakeDestination()
        fake.script(.fail(.transient("http_500")), .fail(.transient("http_500")))
        let slip = try h.readySlip([nas])
        let outbox = h.outbox([nas.id: fake])

        await outbox.drain()
        var row = try h.delivery(slip, nas)
        #expect(row.status == .pending)
        #expect(row.attempts == 1)
        #expect(row.lastErrorCode == "http_500")
        #expect(row.nextAttemptAt == h.clock.now.addingTimeInterval(30))

        // Not due yet: nothing happens.
        h.clock.advance(29)
        #expect(await outbox.drain().retryLater == 0)
        h.clock.advance(1)
        await outbox.drain()
        row = try h.delivery(slip, nas)
        #expect(row.attempts == 2)
        #expect(row.nextAttemptAt == h.clock.now.addingTimeInterval(120))

        h.clock.advance(120)
        #expect(await outbox.drain().delivered == 1)
        #expect(try h.delivery(slip, nas).status == .done)
        #expect(fake.writes == 1)
    }

    @Test func backoffScheduleAndGivingUp() async throws {
        #expect([1, 2, 3, 4, 5, 6, 19].map(Outbox.delay(afterAttempts:)) == [30, 120, 600, 3600, 21_600, 21_600, 21_600])
        let h = try OutboxHarness()
        let nas = try h.destination("NAS")
        let fake = FakeDestination()
        for _ in 0..<Outbox.maxAttempts { fake.script(.fail(.transient("http_503"))) }
        let slip = try h.readySlip([nas])
        let outbox = h.outbox([nas.id: fake])
        for _ in 0..<Outbox.maxAttempts {
            await outbox.drain()
            h.clock.advance(21_600)
        }
        let row = try h.delivery(slip, nas)
        #expect(row.status == .failed)
        #expect(row.attempts == 20)
        // Retryable by hand.
        try h.queue.retry(destination: nas.id, now: h.clock.now)
        #expect(await outbox.drain().delivered == 1)
    }

    @Test func timeoutAfterSuccessfulWriteDoesNotDuplicate() async throws {
        let h = try OutboxHarness()
        let nas = try h.destination("NAS")
        let fake = FakeDestination()
        fake.script(.writeThenTimeout)
        let slip = try h.readySlip([nas])
        let outbox = h.outbox([nas.id: fake])

        #expect(await outbox.drain().retryLater == 1)
        h.clock.advance(30)
        let report = await outbox.drain()
        #expect(report.alreadyThere == 1)
        #expect(report.delivered == 0)
        #expect(fake.writes == 1)
        #expect(fake.stored.count == 1)
        #expect(try h.delivery(slip, nas).status == .done)
    }

    @Test func unauthorizedStopsTheDestination() async throws {
        let h = try OutboxHarness()
        let nas = try h.destination("NAS")
        let fake = FakeDestination()
        fake.script(.fail(.unauthorized))
        let a = try h.readySlip([nas]), b = try h.readySlip([nas])
        let outbox = h.outbox([nas.id: fake])

        let report = await outbox.drain()
        #expect(report.needsAuth == 2)
        #expect(try h.delivery(a, nas).status == .needsAuth)
        #expect(try h.delivery(b, nas).status == .needsAuth)
        #expect(fake.writes == 0)
        // Still stopped on the next drain.
        h.clock.advance(3600)
        #expect(await outbox.drain().delivered == 0)

        // Signed in again.
        try h.queue.retry(destination: nas.id, now: h.clock.now)
        #expect(await outbox.drain().delivered == 2)
    }

    @Test func probeNeedsAuthMarksRows() async throws {
        let h = try OutboxHarness()
        let folder = try h.destination("Folder", type: .folder)
        let fake = FakeDestination()
        fake.reachability = .needsAuth
        let slip = try h.readySlip([folder])
        await h.outbox([folder.id: fake]).drain()
        #expect(try h.delivery(slip, folder).status == .needsAuth)
    }

    @Test func oneBadDestinationDoesNotBlockAnother() async throws {
        let h = try OutboxHarness()
        let bad = try h.destination("Bad"), good = try h.destination("Good")
        let badFake = FakeDestination(name: "bad"), goodFake = FakeDestination(name: "good")
        badFake.script(.fail(.transient("http_500")), .fail(.transient("http_500")), .fail(.transient("http_500")))
        let slips = try (0..<3).map { _ in try h.readySlip([bad, good]) }
        let report = await h.outbox([bad.id: badFake, good.id: goodFake]).drain()
        #expect(report.delivered == 3)
        #expect(report.retryLater == 3)
        for s in slips {
            #expect(try h.delivery(s, good).status == .done)
            #expect(try h.delivery(s, bad).status == .pending)
        }
    }

    @Test func permanentErrorFailsAtOnce() async throws {
        let h = try OutboxHarness()
        let nas = try h.destination("NAS")
        let fake = FakeDestination()
        fake.script(.fail(.permanent("http_403")))
        let slip = try h.readySlip([nas])
        await h.outbox([nas.id: fake]).drain()
        let row = try h.delivery(slip, nas)
        #expect(row.status == .failed)
        #expect(row.lastErrorCode == "http_403")
    }

    @Test func appRestartMidFlight() async throws {
        let h = try OutboxHarness()
        let nas = try h.destination("NAS")
        let fake = FakeDestination()
        let slip = try h.readySlip([nas])
        // The previous process claimed the row, wrote the file, then died before recording it.
        try await h.db.writer.write { db in
            try db.execute(sql: "UPDATE deliveries SET status = 'in_flight', updated_at = ?", arguments: [h.clock.now])
        }
        _ = try await fake.deliver(DeliveryItem(slip: slip, destination: nas, pdfURL: h.files.url(for: slip.pdfPath),
                                                sha256: slip.pdfSha256, byteCount: 0, previousRef: nil))

        let restarted = h.outbox([nas.id: fake])
        // Fresh in-flight rows are left alone: they may belong to a live upload.
        #expect(await restarted.drain() == Outbox.DrainReport())
        #expect(try h.delivery(slip, nas).status == .inFlight)

        h.clock.advance(Outbox.staleInFlight + 1)
        let report = await restarted.drain()
        #expect(report.alreadyThere == 1)
        #expect(fake.writes == 1)
        #expect(try h.delivery(slip, nas).status == .done)
    }

    @Test func tamperedFileIsNotDelivered() async throws {
        let h = try OutboxHarness()
        let nas = try h.destination("NAS")
        let fake = FakeDestination()
        let slip = try h.readySlip([nas])
        try h.files.write(Data("changed".utf8), to: slip.pdfPath)
        await h.outbox([nas.id: fake]).drain()
        #expect(try h.delivery(slip, nas).status == .failed)
        #expect(try h.delivery(slip, nas).lastErrorCode == "hash_mismatch")
        #expect(fake.writes == 0)
    }

    @Test func draftsAndDisabledDestinationsWait() async throws {
        let h = try OutboxHarness()
        let nas = try h.destination("NAS")
        let fake = FakeDestination()
        let slip = try h.readySlip([nas])
        try await h.db.writer.write { db in try db.execute(sql: "UPDATE destinations SET enabled = 0") }
        #expect(await h.outbox([nas.id: fake]).drain().delivered == 0)
        try await h.db.writer.write { db in
            try db.execute(sql: "UPDATE destinations SET enabled = 1")
            try db.execute(sql: "UPDATE slips SET status = 'draft'")
        }
        #expect(await h.outbox([nas.id: fake]).drain().delivered == 0)
        #expect(try h.delivery(slip, nas).status == .pending)
    }

    @Test func wifiOnlyWaitsForWiFi() async throws {
        let h = try OutboxHarness()
        let nas = try h.destination("NAS", wifiOnly: true)
        let fake = FakeDestination()
        try h.readySlip([nas])
        #expect(await h.outbox([nas.id: fake], network: .init(isWiFi: false, isConstrained: false)).drain().delivered == 0)
        #expect(await h.outbox([nas.id: fake], network: .init(isWiFi: true, isConstrained: true)).drain().delivered == 0)
        #expect(await h.outbox([nas.id: fake], network: .init(isWiFi: true, isConstrained: false)).drain().delivered == 1)
    }

    @Test func concurrencyOnePerDestinationThreeOverall() async throws {
        let h = try OutboxHarness()
        let tracker = ConcurrencyTracker()
        var adapters: [UUID: FakeDestination] = [:]
        var destinations: [Destination] = []
        for i in 0..<5 {
            let d = try h.destination("D\(i)")
            let fake = FakeDestination(name: "d\(i)", tracker: tracker)
            for _ in 0..<3 { fake.script(.slow(20_000_000)) }
            adapters[d.id] = fake
            destinations.append(d)
        }
        for _ in 0..<3 { try h.readySlip(destinations) }
        let report = await h.outbox(adapters).drain()
        #expect(report.delivered == 15)
        #expect(adapters.values.allSatisfy { $0.maxActive == 1 })
        #expect(await tracker.maxActive <= Outbox.globalConcurrency)
        #expect(await tracker.maxActive >= 2)
    }

    @Test func concurrentDrainsDoNotDuplicate() async throws {
        let h = try OutboxHarness()
        let nas = try h.destination("NAS")
        let fake = FakeDestination()
        fake.script(.slow(30_000_000))
        try h.readySlip([nas])
        let outbox = h.outbox([nas.id: fake])
        async let a = outbox.drain()
        async let b = outbox.drain()
        _ = await (a, b)
        #expect(fake.writes == 1)
    }

    @Test func nextDueDate() async throws {
        let h = try OutboxHarness()
        let nas = try h.destination("NAS")
        let fake = FakeDestination()
        fake.script(.fail(.transient("offline")))
        try h.readySlip([nas])
        let outbox = h.outbox([nas.id: fake])
        await outbox.drain()
        #expect(try await outbox.nextDueDate() == h.clock.now.addingTimeInterval(30))
    }
}

@Suite struct DeliveryQueueTests {
    @Test func editAfterDeliveryRequeuesFieldDependentDestinations() throws {
        let h = try OutboxHarness()
        let sidecar = try h.destination("Sidecar", config: [Destination.sidecarKey: "1"])
        let byName = try h.destination("ByName")
        let plain = Destination(profileId: h.profile.id, type: .webdav, name: "Plain", namingRule: "slips/{id8}.pdf", enabled: true)
        try h.db.writer.write { try plain.insert($0) }
        let slip = try h.readySlip([sidecar, byName, plain])
        try h.db.writer.write { db in try db.execute(sql: "UPDATE deliveries SET status = 'done', remote_ref = 'old'") }

        let files = h.files
        let store = SlipStore(database: h.db, files: files)
        var edited = slip
        edited.kind = .personal
        edited.subcategoryId = try ReferenceData(database: h.db).snapshot(profile: h.profile.id).subcategories.first!.id
        try store.markReady(edited, now: h.clock.now)
        #expect(try h.delivery(slip, sidecar).status == .pending)
        #expect(try h.delivery(slip, byName).status == .pending)
        #expect(try h.delivery(slip, sidecar).remoteRef == "old")
        #expect(try h.delivery(slip, plain).status == .done)

        // Saving again without a change re-queues nothing.
        try h.db.writer.write { db in try db.execute(sql: "UPDATE deliveries SET status = 'done'") }
        try store.markReady(edited, now: h.clock.now)
        #expect(try h.delivery(slip, byName).status == .done)
    }

    @Test func previousRefReachesTheAdapter() async throws {
        let h = try OutboxHarness()
        let nas = try h.destination("NAS")
        let slip = try h.readySlip([nas])
        try await h.db.writer.write { db in try db.execute(sql: "UPDATE deliveries SET remote_ref = 'before'") }
        let row = try h.delivery(slip, nas)
        let item = try await h.outbox([:]).makeItem(row, destination: nas)
        #expect(item.previousRef == RemoteRef("before"))
    }

    @Test func backlogQueuedWhenADestinationIsTurnedOn() throws {
        let h = try OutboxHarness()
        try h.readySlip([])
        try h.readySlip([])
        let icloud = try h.db.writer.read { try Destination.filter(Column("type") == "icloud").fetchOne($0)! }
        #expect(try h.queue.enqueueBacklog(destination: icloud.id) == 0) // off
        try h.db.writer.write { db in try db.execute(sql: "UPDATE destinations SET enabled = 1 WHERE type = 'icloud'") }
        #expect(try h.queue.enqueueBacklog(destination: icloud.id) == 2)
        #expect(try h.queue.enqueueBacklog(destination: icloud.id) == 0)
        let library = try h.db.writer.read { try Destination.filter(Column("type") == "library").fetchOne($0)! }
        #expect(try h.queue.enqueueBacklog(destination: library.id) == 0)
    }

    @Test func summaries() async throws {
        let h = try OutboxHarness()
        let nas = try h.destination("NAS")
        let fake = FakeDestination()
        fake.script(.ok, .fail(.permanent("http_404")))
        try h.readySlip([nas]); try h.readySlip([nas]); try h.readySlip([nas])
        fake.script(.fail(.transient("x")))
        await h.outbox([nas.id: fake]).drain()
        let s = try #require(try h.queue.summaries(profile: h.profile.id)[nas.id])
        #expect(s.done == 1)
        #expect(s.failed == 1)
        #expect(s.pending == 1)
        #expect(s.waiting == 2)
        #expect(s.lastErrorCode == "http_404")
    }
}
