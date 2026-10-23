import BackgroundTasks
import Network
import SlipsCore
import os

/// Runs the outbox on the triggers of plan §6: app foreground, network path changes, a background
/// refresh task, a save, and the next due retry. The deliveries themselves are `Outbox`'s.
@MainActor
final class DeliveryScheduler {
    static let backgroundTaskId = "com.etzian.slips.outbox"
    private static let log = Logger(subsystem: "com.etzian.slips", category: "outbox")

    let outbox: Outbox
    private let monitor = NWPathMonitor()
    private let conditions = NetworkState()
    private var timer: Task<Void, Never>?

    init(database: AppDatabase, files: FileStore, adapters: @escaping Outbox.AdapterProvider) {
        let conditions = self.conditions
        outbox = Outbox(database: database, files: files, adapters: adapters, network: { conditions.current })
        monitor.pathUpdateHandler = { [weak self] path in
            let usable = path.status == .satisfied
            conditions.update(NetworkConditions(isWiFi: path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet),
                                                isConstrained: path.isConstrained))
            if usable {
                Task { @MainActor in self?.trigger("network") }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.etzian.slips.path"))
    }

    /// Drains now, then arms a timer for the next due retry.
    func trigger(_ reason: String) {
        Self.log.debug("drain: \(reason, privacy: .public)")
        let outbox = self.outbox
        Task {
            await outbox.drain()
            await self.armTimer()
        }
    }

    private func armTimer() async {
        timer?.cancel()
        guard let due = try? await outbox.nextDueDate() else { return }
        let delay = max(due.timeIntervalSinceNow, 1)
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.trigger("retry")
        }
    }

    // MARK: Background refresh

    /// Registers the handler. Must run before the app finishes launching.
    static func registerBackgroundTask(_ scheduler: @escaping @MainActor @Sendable () -> DeliveryScheduler?) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskId, using: .main) { task in
            MainActor.assumeIsolated { handle(task, scheduler: scheduler()) }
        }
    }

    private static func handle(_ task: BGTask, scheduler: DeliveryScheduler?) {
        guard let outbox = scheduler?.outbox else { return task.setTaskCompleted(success: false) }
        let work = Task { await outbox.drain() }
        task.expirationHandler = { work.cancel() }
        Task {
            _ = await work.value
            task.setTaskCompleted(success: !work.isCancelled)
            scheduleBackgroundRefresh()
        }
    }

    /// Asks iOS for a background run in about 15 minutes, when something waits.
    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            log.notice("background refresh not scheduled: \(String(describing: error), privacy: .public)")
        }
    }
}

/// The latest path conditions, read by the outbox from any thread.
final class NetworkState: Sendable {
    // Mutex-guarded value; `OSAllocatedUnfairLock` is Sendable.
    private let state = OSAllocatedUnfairLock(initialState: NetworkConditions(isWiFi: false, isConstrained: false))

    var current: NetworkConditions { state.withLock { $0 } }

    func update(_ value: NetworkConditions) {
        state.withLock { $0 = value }
    }
}
