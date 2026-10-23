import SwiftUI

struct CapturePlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("capture.title", systemImage: "doc.viewfinder")
            } description: {
                Text("capture.message")
            }
            .navigationTitle(Text("tab.capture"))
        }
    }
}
