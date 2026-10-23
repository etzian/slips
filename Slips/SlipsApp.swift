import SwiftUI

@main
struct SlipsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let model = AppModel.live()
        AppModel.current = model
        _model = State(initialValue: model)
        DeliveryScheduler.registerBackgroundTask { AppModel.current?.scheduler }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(appearance.colorScheme)
                .tint(EZ.Color.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.scheduler.trigger("foreground")
            case .background: DeliveryScheduler.scheduleBackgroundRefresh()
            default: break
            }
        }
    }
}
