import Foundation
import Observation
import SlipsCore
import os

/// The app's single source of state: the database, the file store and the active profile.
@MainActor
@Observable
final class AppModel {
    let database: AppDatabase
    let files: FileStore
    let reference: ReferenceData
    let capture: CaptureStore
    let slips: SlipStore
    let deliveries: DeliveryQueue
    let destinations: DestinationStore
    let scheduler: DeliveryScheduler
    private(set) var activeProfileId: UUID?
    /// Set when the database could not be opened; the shell shows it instead of the tabs.
    private(set) var startupError: String?

    private let defaults: UserDefaults
    private static let activeProfileKey = "activeProfileId"
    nonisolated static let log = Logger(subsystem: "com.etzian.slips", category: "app")

    init(database: AppDatabase, files: FileStore, defaults: UserDefaults = .standard) {
        self.database = database
        self.files = files
        self.reference = ReferenceData(database: database)
        self.capture = CaptureStore(database: database, files: files)
        self.slips = SlipStore(database: database, files: files)
        self.deliveries = DeliveryQueue(database: database)
        self.destinations = DestinationStore(database: database)
        self.scheduler = DeliveryScheduler(database: database, files: files, adapters: DestinationAdapters.make)
        self.defaults = defaults
        self.firstRunDone = FirstRunState(defaults: defaults).isDone
        bootstrap()
    }

    /// The on-device model: database and slip files under Application Support. UI tests launch with
    /// `-uiTesting` and get an empty in-memory database and a temporary folder instead.
    static func live() -> AppModel {
        let fm = FileManager.default
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            let tmp = fm.temporaryDirectory.appendingPathComponent("ui-\(UUID().uuidString)")
            let defaults = UserDefaults(suiteName: "ui-tests") ?? .standard
            defaults.removePersistentDomain(forName: "ui-tests")
            // UI tests start past the first-run screen unless they test it.
            if !ProcessInfo.processInfo.arguments.contains("-firstRun") { FirstRunState(defaults: defaults).markDone() }
            // An in-memory database cannot fail to open.
            return AppModel(database: try! AppDatabase.inMemory(), files: FileStore(root: tmp), defaults: defaults)
        }
        do {
            // Never fall back to the temporary folder: iOS may purge it, and slips would be lost.
            let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let db = try AppDatabase.onDisk(directory: support)
            return AppModel(database: db, files: FileStore(root: support))
        } catch {
            log.error("database open failed: \(String(describing: error), privacy: .private)")
            // The shell shows the startup error and nothing else, so nothing is ever written here.
            let model = AppModel(database: try! AppDatabase.inMemory(),
                                 files: FileStore(root: fm.temporaryDirectory.appendingPathComponent("unavailable")))
            model.startupError = String(describing: error)
            return model
        }
    }

    /// Images and PDFs another app (or a drop on the simulator) asked us to open; the capture screen
    /// imports them and empties the list.
    var openedFiles: [URL] = []

    /// The running app's model, for the background task handler (registered before any view exists).
    static var current: AppModel?

    static func preview() -> AppModel {
        AppModel(database: try! AppDatabase.inMemory(),
                 files: FileStore(root: FileManager.default.temporaryDirectory),
                 defaults: UserDefaults(suiteName: "previews") ?? .standard)
    }

    /// Makes sure one profile exists and one is active.
    func bootstrap() {
        do {
            var profiles = try database.profiles()
            if profiles.isEmpty {
                try reference.createProfile(name: String(localized: "profile.defaultName"), seedNames: Self.seedNames)
                profiles = try database.profiles()
            }
            let stored = defaults.string(forKey: Self.activeProfileKey).flatMap(UUID.init(uuidString:))
            activeProfileId = profiles.first { $0.id == stored }?.id ?? profiles.first?.id
            ExportFiles.purge()
            // Before capture is offered: drop files of captures killed before their row, flag lost files.
            let report = try capture.sweep()
            if report.orphanFoldersRemoved + report.rowsMissingFile > 0 {
                Self.log.notice("sweep: \(report.orphanFoldersRemoved) orphan folder(s), \(report.rowsMissingFile) missing file(s)")
            }
        } catch {
            Self.log.error("bootstrap failed: \(String(describing: error), privacy: .private)")
            startupError = String(describing: error)
        }
    }

    /// Erase all data on this iPhone: rows, slip files, Keychain items, preferences. Delivered copies
    /// stay where they are. The app then starts over with a fresh profile and the first-run screen.
    func eraseAll() throws {
        let destinations = try Eraser(database: database, files: files).eraseAll()
        destinations.forEach(Keychain.delete)
        for key in [Self.activeProfileKey, FirstRunState.key, AppLock.key, Appearance.storageKey] {
            defaults.removeObject(forKey: key)
        }
        activeProfileId = nil
        bootstrap()
        firstRunDone = false
    }

    /// Mirrors `FirstRunState` so the shell re-renders when it changes.
    var firstRunDone = false {
        didSet {
            if firstRunDone { FirstRunState(defaults: defaults).markDone() } else { FirstRunState(defaults: defaults).reset() }
        }
    }

    func setActiveProfile(_ id: UUID) {
        activeProfileId = id
        defaults.set(id.uuidString, forKey: Self.activeProfileKey)
    }

    /// The names the seeded destinations get, in the user's language at creation time.
    static var seedNames: AppDatabase.SeedNames {
        AppDatabase.SeedNames(library: String(localized: "destinationType.library"),
                              icloud: String(localized: "destinationType.icloud"))
    }
}
