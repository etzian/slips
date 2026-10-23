import SwiftUI

@main
struct SlipsApp: App {
    @State private var model = AppModel.live()
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(appearance.colorScheme)
                .tint(EZ.Color.accent)
        }
    }
}
