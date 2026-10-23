import SwiftUI

/// The shell: a bottom tab bar with Library, Capture and Settings (plan §10), the first-run screen
/// once, and the optional lock.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppLock.key) private var lockOn = false
    @State private var tab: Tab = .library
    @State private var locked = UserDefaults.standard.bool(forKey: AppLock.key)

    enum Tab: Hashable { case library, capture, settings }

    var body: some View {
        if let error = model.startupError {
            ErrorStateView(title: "error.startup.title", message: "error.startup.message", detail: error, retry: nil)
        } else {
            TabView(selection: $tab) {
                LibraryView()
                    .tabItem { Label("tab.library", systemImage: "tray.full") }
                    .tag(Tab.library)
                CaptureView()
                    .tabItem { Label("tab.capture", systemImage: "doc.viewfinder") }
                    .tag(Tab.capture)
                SettingsView()
                    .tabItem { Label("tab.settings", systemImage: "gearshape") }
                    .tag(Tab.settings)
            }
            .fullScreenCover(isPresented: Binding(get: { !model.firstRunDone }, set: { _ in })) {
                FirstRunView { model.firstRunDone = true }
            }
            .overlay {
                if lockOn && locked {
                    LockView { Task { if await AppLock.authenticate() { locked = false } } }
                }
            }
            .onOpenURL { url in
                guard url.isFileURL else { return }
                model.openedFiles.append(url)
                tab = .capture
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background && lockOn { locked = true }
            }
        }
    }
}
