import SlipsCore
import SwiftUI

/// Sub-categories grouped by kind. Seeded rows show fin's translated name; the user may rename any
/// row and add their own. Removing a seeded or used row archives it; the two transfer keys stay.
struct SubcategoriesView: View {
    let profileId: UUID
    @Environment(AppModel.self) private var model
    @State private var state: Loadable<[Subcategory]> = .loading
    @State private var prompt: TextPrompt?
    @State private var error: LocalizedStringKey?
    @State private var notice: LocalizedStringKey?
    @State private var reload = 0

    var body: some View {
        content
            .navigationTitle(Text("subcategories.title"))
            .textPrompt($prompt)
            .errorAlert($error)
            .safeAreaInset(edge: .bottom) { NoticeBanner(text: $notice) }
            .task(id: reload) {
                do {
                    for try await list in model.reference.observeSubcategories(profile: profileId) { state = .loaded(list) }
                } catch {
                    state = .failed(String(describing: error))
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            SkeletonList(rows: 10)
        case .failed(let detail):
            ErrorStateView(title: "error.load.title", message: "error.load.message", detail: detail) { reload += 1 }
        case .loaded(let items):
            List {
                ForEach(SubcategoryKind.allCases, id: \.self) { kind in
                    Section {
                        ForEach(items.filter { $0.kind == kind && $0.archivedAt == nil }) { row($0) }
                        Button {
                            add(kind)
                        } label: {
                            Label("subcategories.new", systemImage: "plus")
                        }
                    } header: {
                        Text(kind.title)
                    }
                }
                let archived = items.filter { $0.archivedAt != nil }
                if !archived.isEmpty {
                    Section("section.archived") {
                        ForEach(archived) { s in
                            Text(s.displayName)
                                .foregroundStyle(.secondary)
                                .swipeActions {
                                    Button("action.restore") {
                                        attempt($error) { try model.reference.unarchiveSubcategory(s.id) }
                                    }.tint(EZ.Color.accent)
                                }
                        }
                    }
                }
            }
        }
    }

    private func row(_ s: Subcategory) -> some View {
        Text(s.displayName)
            .swipeActions {
                if !(s.nameKey.map(Seed.transferKeys.contains) ?? false) {
                    Button("action.remove", role: .destructive) { remove(s) }
                }
                Button("action.rename") { rename(s) }.tint(EZ.Color.accent)
            }
    }

    private func add(_ kind: SubcategoryKind) {
        prompt = TextPrompt(title: "subcategories.new", text: "", confirm: "action.create") { name in
            attempt($error) { try model.reference.addSubcategory(profile: profileId, kind: kind, name: name) }
        }
    }

    private func rename(_ s: Subcategory) {
        prompt = TextPrompt(title: s.nameKey == nil ? "action.rename" : "subcategories.renameSeeded",
                            text: s.customName ?? s.displayName, confirm: "action.save") { name in
            attempt($error) { try model.reference.renameSubcategory(s.id, to: name) }
        }
    }

    private func remove(_ s: Subcategory) {
        attempt($error) {
            if try model.reference.removeSubcategory(s.id) == .archived { notice = "notice.archivedKept" }
        }
    }
}
