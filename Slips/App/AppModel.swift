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
    private(set) var activeProfileId: UUID?
    /// Set when the database could not be opened; the shell shows it instead of the tabs.
    private(set) var startupError: String?

    private let defaults: UserDefaults
    private static let activeProfileKey = "activeProfileId"
    static let log = Logger(subsystem: "com.etzian.slips", category: "app")

    init(database: AppDatabase, files: FileStore, defaults: UserDefaults = .standard) {
        self.database = database
        self.files = files
        self.reference = ReferenceData(database: database)
        self.defaults = defaults
        bootstrap()
    }

    /// The on-device model: database and slip files under Application Support. UI tests launch with
    /// `-uiTesting` and get an empty in-memory database and a temporary folder instead.
    static func live() -> AppModel {
        let fm = FileManager.default
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            let tmp = fm.temporaryDirectory.appendingPathComponent("ui-\(UUID().uuidString)")
            // An in-memory database cannot fail to open.
            return AppModel(database: try! AppDatabase.inMemory(), files: FileStore(root: tmp),
                            defaults: UserDefaults(suiteName: "ui-tests") ?? .standard)
        }
        let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        do {
            let db = try AppDatabase.onDisk(directory: support)
            return AppModel(database: db, files: FileStore(root: support))
        } catch {
            log.error("database open failed: \(String(describing: error), privacy: .private)")
            let model = AppModel(database: try! AppDatabase.inMemory(), files: FileStore(root: support))
            model.startupError = String(describing: error)
            return model
        }
    }

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
        } catch {
            Self.log.error("bootstrap failed: \(String(describing: error), privacy: .private)")
            startupError = String(describing: error)
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
