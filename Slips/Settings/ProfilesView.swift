import SlipsCore
import SwiftUI

/// Profiles: list, create, rename, switch the active one.
struct ProfilesView: View {
    @Environment(AppModel.self) private var model
    @State private var state: Loadable<[Profile]> = .loading
    @State private var prompt: TextPrompt?
    @State private var error: LocalizedStringKey?
    @State private var reload = 0

    var body: some View {
        content
            .navigationTitle(Text("profiles.title"))
            .toolbar {
                Button {
                    prompt = TextPrompt(title: "profiles.new", text: "", confirm: "action.create") { name in
                        attempt($error) {
                            let p = try model.reference.createProfile(name: name, seedNames: AppModel.seedNames)
                            model.setActiveProfile(p.id)
                        }
                    }
                } label: {
                    Label("profiles.new", systemImage: "plus")
                }
            }
            .textPrompt($prompt)
            .errorAlert($error)
            .task(id: reload) {
                do {
                    for try await list in model.reference.observeProfiles() { state = .loaded(list) }
                } catch {
                    state = .failed(String(describing: error))
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            SkeletonList(rows: 2)
        case .failed(let detail):
            ErrorStateView(title: "error.load.title", message: "error.load.message", detail: detail) { reload += 1 }
        case .loaded(let profiles):
            List {
                Section {
                    ForEach(profiles) { profile in
                        Button {
                            model.setActiveProfile(profile.id)
                        } label: {
                            HStack {
                                Text(profile.name).foregroundStyle(EZ.Color.text)
                                Spacer()
                                if profile.id == model.activeProfileId {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                        .accessibilityLabel(Text("profiles.active"))
                                }
                            }
                        }
                        .accessibilityAddTraits(profile.id == model.activeProfileId ? .isSelected : [])
                        .swipeActions {
                            Button("action.rename") { rename(profile) }.tint(EZ.Color.accent)
                        }
                        .contextMenu {
                            Button("action.rename") { rename(profile) }
                        }
                    }
                } footer: {
                    Text("profiles.footer")
                }
            }
        }
    }

    private func rename(_ profile: Profile) {
        prompt = TextPrompt(title: "action.rename", text: profile.name, confirm: "action.save") { name in
            attempt($error) { try model.reference.renameProfile(profile.id, to: name) }
        }
    }
}
