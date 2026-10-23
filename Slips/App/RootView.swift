import SwiftUI

/// The shell: a bottom tab bar with Library, Capture and Settings (plan §10).
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .library

    enum Tab: Hashable { case library, capture, settings }

    var body: some View {
        if let error = model.startupError {
            ErrorStateView(title: "error.startup.title", message: "error.startup.message", detail: error, retry: nil)
        } else {
            TabView(selection: $tab) {
                LibraryPlaceholderView()
                    .tabItem { Label("tab.library", systemImage: "tray.full") }
                    .tag(Tab.library)
                CapturePlaceholderView()
                    .tabItem { Label("tab.capture", systemImage: "doc.viewfinder") }
                    .tag(Tab.capture)
                SettingsView()
                    .tabItem { Label("tab.settings", systemImage: "gearshape") }
                    .tag(Tab.settings)
            }
        }
    }
}
