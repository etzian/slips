import SwiftUI

struct LibraryPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("library.empty.title", systemImage: "tray")
            } description: {
                Text("library.empty.message")
            }
            .navigationTitle(Text("tab.library"))
        }
        .accessibilityIdentifier("library")
    }
}
