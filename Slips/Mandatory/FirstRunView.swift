import SwiftUI

/// Whether the first-run screen was seen. One flag in UserDefaults; erasing the data clears it.
struct FirstRunState {
    static let key = "firstRunDone"
    let defaults: UserDefaults

    var isDone: Bool { defaults.bool(forKey: Self.key) }
    func markDone() { defaults.set(true, forKey: Self.key) }
    func reset() { defaults.removeObject(forKey: Self.key) }
}

/// Shown once: the app's name and what it does, privacy in plain words, one button. The language is
/// not asked: iOS sets it per app.
struct FirstRunView: View {
    let done: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EZ.Space.lg) {
                Image(systemName: "doc.viewfinder")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(AppInfo.name)
                    .font(.largeTitle.bold())
                Text("firstRun.pitch")
                    .font(.title3)
                VStack(alignment: .leading, spacing: EZ.Space.md) {
                    Label("firstRun.privacy.device", systemImage: "iphone")
                    Label("firstRun.privacy.destinations", systemImage: "arrow.up.forward.app")
                    Label("firstRun.privacy.nothingElse", systemImage: "hand.raised")
                }
                .font(.body)
            }
            .padding(EZ.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: done) {
                Text("firstRun.start").frame(maxWidth: .infinity, minHeight: Metrics.minTouchTarget)
            }
            .buttonStyle(.borderedProminent)
            .padding(EZ.Space.lg)
            .accessibilityIdentifier("firstRun.start")
        }
        .background(EZ.Color.bg)
    }
}

/// The app's name and version from the bundle (never typed in a string).
enum AppInfo {
    static var name: String {
        Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleName"] as? String ?? ""
    }

    static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return "\(v) (\(b))"
    }

    static var copyright: String {
        Company.copyrightTemplate.replacingOccurrences(of: "{year}", with: String(Calendar.current.component(.year, from: Date())))
    }

    static var endorsement: String {
        Locale.current.language.languageCode?.identifier == "fr" ? Company.endorsementFR : Company.endorsementEN
    }

    static var privacyOfficerTitle: String {
        Locale.current.language.languageCode?.identifier == "fr" ? Company.privacyOfficerTitleFR : Company.privacyOfficerTitleEN
    }
}
