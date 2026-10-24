import LocalAuthentication
import SlipsCore
import SwiftUI

/// Settings › Privacy: the optional lock, what is stored where, what each destination receives (the
/// same content as `legal/data-map.yaml`), the privacy officer, and export.
struct PrivacyView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppLock.key) private var lockOn = false
    @AppStorage(OnDeviceAI.settingKey) private var aiOnDevice = true
    @State private var destinations: [Destination] = []
    @State private var lockError: LocalizedStringKey?

    var body: some View {
        List {
            Section {
                Toggle("privacy.lock", isOn: lockBinding)
            } footer: {
                Text("privacy.lock.footer")
            }
            Section("privacy.stored") {
                Text("privacy.stored.device")
                Text("privacy.stored.keychain")
                Text("privacy.stored.backup")
            }
            Section("privacy.sent") {
                Text("privacy.sent.offByDefault")
                ForEach(destinations.filter { $0.type != .library }) { d in
                    LabeledContent {
                        Text(d.enabled ? LocalizedStringKey("privacy.on") : "privacy.off")
                    } label: {
                        VStack(alignment: .leading, spacing: EZ.Space.xs2) {
                            Text(verbatim: d.name)
                            Text(d.type.receives).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("privacy.sent.never")
            }
            Section("privacy.processing") {
                Text("privacy.processing.ocr")
            }
            Section {
                Toggle("ai.onDevice.toggle", isOn: $aiOnDevice)
                    .accessibilityIdentifier("ai.onDevice.toggle")
                if let profile = model.activeProfileId {
                    NavigationLink("ai.endpoint.title") { AIEndpointView(profileId: profile) }
                }
            } header: {
                Text("ai.section")
            } footer: {
                VStack(alignment: .leading, spacing: EZ.Space.xs2) {
                    Text("ai.onDevice.footer")
                    Text(verbatim: OnDeviceAI.status.message)
                }
            }
            Section("privacy.officer") {
                Text(verbatim: Company.privacyOfficerName)
                Text(verbatim: AppInfo.privacyOfficerTitle).font(.footnote).foregroundStyle(.secondary)
                if let mail = URL(string: "mailto:\(Company.privacyEmail)") {
                    Link(Company.privacyEmail, destination: mail)
                }
            }
        }
        .navigationTitle(Text("settings.privacy"))
        .errorAlert($lockError)
        .task {
            if let profile = model.activeProfileId { destinations = (try? model.destinations.list(profile: profile)) ?? [] }
        }
    }

    /// Turning the lock on asks for Face ID (or the passcode) once, so nobody locks themselves out.
    private var lockBinding: Binding<Bool> {
        Binding {
            lockOn
        } set: { on in
            guard on else { lockOn = false; return }
            Task {
                if await AppLock.authenticate() { lockOn = true } else { lockError = "privacy.lock.unavailable" }
            }
        }
    }
}

extension DestinationType {
    var receives: LocalizedStringKey {
        switch self {
        case .library: "privacy.receives.library"
        case .icloud: "privacy.receives.icloud"
        case .folder: "privacy.receives.folder"
        case .webdav: "privacy.receives.webdav"
        case .fin, .dropbox, .onedrive, .gdrive: "privacy.receives.other"
        }
    }
}

/// The optional Face ID / passcode lock.
enum AppLock {
    static let key = "appLock"

    static func authenticate() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                  localizedReason: String(localized: "lock.reason"))) ?? false
    }
}

/// Covers the app until the user unlocks it.
struct LockView: View {
    let unlock: () -> Void

    var body: some View {
        VStack(spacing: EZ.Space.lg) {
            Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.tint).accessibilityHidden(true)
            Text("lock.title").font(.title2.bold())
            Button(action: unlock) {
                Text("lock.unlock").frame(minWidth: Metrics.minTouchTarget * 4, minHeight: Metrics.minTouchTarget)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EZ.Color.bg)
    }
}
