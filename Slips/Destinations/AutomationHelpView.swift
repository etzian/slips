import SwiftUI

/// How to make the Shortcuts automation that sends slips when the phone joins the home Wi-Fi.
struct AutomationHelpView: View {
    var body: some View {
        List {
            Section {
                Text("automation.intro")
            }
            Section("automation.steps") {
                Label("automation.step1", systemImage: "1.circle")
                Label("automation.step2", systemImage: "2.circle")
                Label("automation.step3", systemImage: "3.circle")
                Label("automation.step4", systemImage: "4.circle")
                Label("automation.step5", systemImage: "5.circle")
            }
            Section {
                Text("automation.note").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(Text("automation.title"))
    }
}
