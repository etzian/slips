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

    var body: some View {
        NavigationStack {
            List {
                Section("settings.general") {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        LabeledContent("settings.language") {
                            Text(Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "") ?? "")
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
                    Text("settings.privacy.placeholder")
                        .foregroundStyle(.secondary)
                }

                Section("settings.about") {
                    Text("settings.about.placeholder")
                        .foregroundStyle(.secondary)
                }

                Section("settings.dangerZone") {
                    Text("settings.dangerZone.placeholder")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(Text("tab.settings"))
            .task {
                do {
                    for try await list in model.reference.observeProfiles() { profiles = .loaded(list) }
                } catch {
                    profiles = .failed(String(describing: error))
                }
            }
        }
    }

    private var activeProfileName: String {
        profiles.value?.first { $0.id == model.activeProfileId }?.name ?? ""
    }
}
