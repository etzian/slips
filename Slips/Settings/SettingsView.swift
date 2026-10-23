import SlipsCore
import SwiftUI
import UIKit

/// Settings root, in the order of plan §10: General, Appearance, Profiles and reference data,
/// Destinations, Privacy, About, Danger zone.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system
    @State private var profiles: Loadable<[Profile]> = .loading
    @State private var confirmErase = false
    @State private var error: LocalizedStringKey?

    var body: some View {
        NavigationStack {
            List {
                Section("settings.general") {
                    Button {
                        // The app's own page in iOS Settings (Settings › Apps › Slips), where its language is chosen.
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: {
                        HStack(spacing: EZ.Space.sm) {
                            VStack(alignment: .leading, spacing: EZ.Space.xs2) {
                                Text("settings.language").foregroundStyle(EZ.Color.text)
                                Text("settings.language.where \(AppInfo.name)").font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: EZ.Space.sm)
                            Text(verbatim: Self.appLanguage).foregroundStyle(.secondary)
                            Image(systemName: "arrow.up.forward.app")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityHint(Text("settings.language.hint"))
                }

                Section("settings.appearance") {
                    Picker("settings.theme", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section("settings.profiles") {
                    NavigationLink {
                        ProfilesView()
                    } label: {
                        LabeledContent("settings.profiles.manage") {
                            Text(activeProfileName)
                        }
                    }
                    if let id = model.activeProfileId {
                        NavigationLink("settings.businesses") { EnterprisesView(profileId: id) }
                        NavigationLink("settings.subcategories") { SubcategoriesView(profileId: id) }
                        NavigationLink("settings.paymentMethods") { PaymentMethodsView(profileId: id) }
                    }
                }

                Section("settings.destinations") {
                    if let id = model.activeProfileId {
                        NavigationLink("settings.destinations.manage") { DestinationsView(profileId: id) }
                    }
                }

                Section("settings.privacy") {
                    NavigationLink("settings.privacy.manage") { PrivacyView() }
                }

                Section("settings.about") {
                    NavigationLink("settings.about.manage") { AboutView() }
                }

                Section {
                    Button("erase.button", role: .destructive) { confirmErase = true }
                        .accessibilityIdentifier("erase.button")
                } header: {
                    Text("settings.dangerZone")
                } footer: {
                    Text("erase.footer")
                }
            }
            .navigationTitle(Text("tab.settings"))
            .confirmationDialog("erase.confirm.title", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("erase.confirm.action", role: .destructive) {
                    attempt($error) { try model.eraseAll() }
                }
            } message: {
                Text("erase.confirm.message")
            }
            .errorAlert($error)
            .task {
                do {
                    for try await list in model.reference.observeProfiles() { profiles = .loaded(list) }
                } catch {
                    profiles = .failed(String(describing: error))
                }
            }
        }
    }

    /// The language the app runs in (the catalog localisation iOS picked), named in that language.
    static var appLanguage: String {
        let code = Bundle.main.preferredLocalizations.first ?? Locale.current.identifier
        let locale = Locale(identifier: code)
        let name = locale.localizedString(forLanguageCode: locale.language.languageCode?.identifier ?? code) ?? code
        return name.prefix(1).uppercased(with: locale) + name.dropFirst()
    }

    private var activeProfileName: String {
        profiles.value?.first { $0.id == model.activeProfileId }?.name ?? ""
    }
}
