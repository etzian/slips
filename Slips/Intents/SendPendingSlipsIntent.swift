import AppIntents
import SlipsCore

/// "Send pending slips": drains the outbox now. Made for a Shortcuts automation such as "When I join
/// my home Wi-Fi → Send pending slips", so a LAN server gets the slips as soon as the phone is home.
struct SendPendingSlipsIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.sendPending.title"
    static let description = IntentDescription("intent.sendPending.description")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.current ?? AppModel.live()
        if AppModel.current == nil { AppModel.current = model }
        let report = await model.scheduler.outbox.drain()
        let waiting = (try? model.deliveries.waitingCount()) ?? 0
        return .result(dialog: "intent.sendPending.result \(report.delivered + report.alreadyThere) \(waiting)")
    }
}
