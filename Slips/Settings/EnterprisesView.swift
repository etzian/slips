import SlipsCore
import SwiftUI

/// Businesses of a profile. Removing one that slips use archives it instead.
struct EnterprisesView: View {
    let profileId: UUID
    @Environment(AppModel.self) private var model
    @State private var state: Loadable<[Enterprise]> = .loading
    @State private var prompt: TextPrompt?
    @State private var error: LocalizedStringKey?
    @State private var notice: LocalizedStringKey?
    @State private var reload = 0

    var body: some View {
        content
            .navigationTitle(Text("businesses.title"))
            .toolbar {
                Button { add() } label: { Label("businesses.new", systemImage: "plus") }
            }
            .textPrompt($prompt)
            .errorAlert($error)
            .safeAreaInset(edge: .bottom) { NoticeBanner(text: $notice) }
            .task(id: reload) {
                do {
                    for try await list in model.reference.observeEnterprises(profile: profileId) { state = .loaded(list) }
                } catch {
                    state = .failed(String(describing: error))
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            SkeletonList()
        case .failed(let detail):
            ErrorStateView(title: "error.load.title", message: "error.load.message", detail: detail) { reload += 1 }
        case .loaded(let items) where items.isEmpty:
            ContentUnavailableView {
                Label("businesses.empty.title", systemImage: "building.2")
            } description: {
                Text("businesses.empty.message")
            } actions: {
                Button("businesses.new") { add() }.buttonStyle(.borderedProminent)
            }
        case .loaded(let items):
            List {
                let active = items.filter { $0.archivedAt == nil }
                let archived = items.filter { $0.archivedAt != nil }
                Section {
                    ForEach(active) { e in
                        Text(e.name)
                            .swipeActions {
                                Button("action.remove", role: .destructive) { remove(e) }
                                Button("action.rename") { rename(e) }.tint(EZ.Color.accent)
                            }
                    }
                }
                if !archived.isEmpty {
                    Section("section.archived") {
                        ForEach(archived) { e in
                            Text(e.name)
                                .foregroundStyle(.secondary)
                                .swipeActions {
                                    Button("action.restore") {
                                        attempt($error) { try model.reference.unarchiveEnterprise(e.id) }
                                    }.tint(EZ.Color.accent)
                                }
                        }
                    }
                }
            }
        }
    }

    private func add() {
        prompt = TextPrompt(title: "businesses.new", text: "", confirm: "action.create") { name in
            attempt($error) { try model.reference.addEnterprise(profile: profileId, name: name) }
        }
    }

    private func rename(_ e: Enterprise) {
        prompt = TextPrompt(title: "action.rename", text: e.name, confirm: "action.save") { name in
            attempt($error) { try model.reference.renameEnterprise(e.id, to: name) }
        }
    }

    private func remove(_ e: Enterprise) {
        attempt($error) {
            if try model.reference.removeEnterprise(e.id) == .archived { notice = "notice.archivedInUse" }
        }
    }
}

/// A short message under the list that the user dismisses, for outcomes that are not errors.
struct NoticeBanner: View {
    @Binding var text: LocalizedStringKey?

    var body: some View {
        if let message = text {
            HStack(alignment: .firstTextBaseline, spacing: EZ.Space.sm) {
                Image(systemName: "info.circle").foregroundStyle(EZ.Color.info)
                Text(message).frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    text = nil
                } label: {
                    Image(systemName: "xmark")
                        .frame(minWidth: Metrics.minTouchTarget, minHeight: Metrics.minTouchTarget)
                }
                .accessibilityLabel(Text("action.dismiss"))
            }
            .padding(.horizontal, EZ.Space.md)
            .background(EZ.Color.surface)
            .accessibilityElement(children: .combine)
        }
    }
}
