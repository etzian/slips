import SlipsCore
import SwiftUI

/// The library: slips by month, search on merchant, notes and OCR text, filters, selection to share
/// or export, and a banner for destinations that need the user.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = LibraryFilter()
    @State private var state: Loadable<[LibraryMonth]> = .loading
    @State private var destinations: [Destination] = []
    @State private var summaries: [UUID: DeliveryQueue.Summary] = [:]
    @State private var showFilters = false
    @State private var showExport = false
    @State private var selection = Set<UUID>()
    @State private var editMode: EditMode = .inactive
    @State private var reload = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("tab.library"))
                .searchable(text: $filter.search, prompt: Text("library.search"))
                .toolbar { toolbar }
                .environment(\.editMode, $editMode)
                .sheet(isPresented: $showFilters) {
                    if let profile = model.activeProfileId {
                        NavigationStack { LibraryFilterView(profileId: profile, filter: $filter) }
                    }
                }
                .sheet(isPresented: $showExport) {
                    if let profile = model.activeProfileId {
                        NavigationStack { ExportView(profileId: profile, filter: filter, only: selection.isEmpty ? nil : selection) }
                    }
                }
                .navigationDestination(for: UUID.self) { SlipDetailView(slipId: $0) }
        }
        .accessibilityIdentifier("library")
        .task(id: TaskKey(profile: model.activeProfileId, filter: filter, reload: reload)) { await observe() }
        .task(id: model.activeProfileId) {
            guard let profile = model.activeProfileId else { return }
            for await d in model.destinations.observe(profile: profile).ignoringErrors() { destinations = d }
        }
        .task(id: model.activeProfileId) {
            guard let profile = model.activeProfileId else { return }
            for await s in model.deliveries.observeSummaries(profile: profile).ignoringErrors() { summaries = s }
        }
    }

    struct TaskKey: Hashable {
        var profile: UUID?
        var filter: LibraryFilter
        var reload: Int
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showFilters = true } label: {
                Label("library.filters", systemImage: filter.isActive ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if editMode.isEditing, !selection.isEmpty {
                ShareLink(items: selectedURLs) { Label("action.share", systemImage: "square.and.arrow.up") }
            }
            Menu {
                Button { showExport = true } label: { Label("library.export", systemImage: "square.and.arrow.up.on.square") }
                Button {
                    withAnimation(reduceMotion ? nil : .default) { editMode = editMode.isEditing ? .inactive : .active }
                    if !editMode.isEditing { selection = [] }
                } label: {
                    Label(editMode.isEditing ? LocalizedStringKey("library.select.done") : "library.select", systemImage: "checkmark.circle")
                }
            } label: {
                Label("library.more", systemImage: "ellipsis.circle")
            }
        }
    }

    private var selectedURLs: [URL] {
        (state.value ?? []).flatMap(\.items).filter { selection.contains($0.id) }.map { model.files.url(for: $0.slip.pdfPath) }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            SkeletonList(rows: 8)
        case .failed(let detail):
            ErrorStateView(title: "error.load.title", message: "error.load.message", detail: detail) { reload += 1 }
        case .loaded(let months) where months.isEmpty && filter.isActive:
            ContentUnavailableView {
                Label("library.emptyFiltered.title", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("library.emptyFiltered.message")
            } actions: {
                Button("library.clearFilters") { filter = LibraryFilter() }.buttonStyle(.borderedProminent)
            }
        case .loaded(let months) where months.isEmpty:
            ContentUnavailableView {
                Label("library.empty.title", systemImage: "tray")
            } description: {
                Text("library.empty.message")
            }
        case .loaded(let months):
            List(selection: $selection) {
                DeliveryBanner(destinations: destinations, summaries: summaries)
                WaitingNote(destinations: destinations, summaries: summaries)
                ForEach(months) { month in
                    Section {
                        ForEach(month.items) { item in
                            NavigationLink(value: item.id) { LibraryRow(item: item) }
                        }
                    } header: {
                        Text(month.title)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func observe() async {
        guard let profile = model.activeProfileId else { return }
        do {
            for try await months in LibraryQuery(database: model.database).observe(profile: profile, filter: filter) {
                state = .loaded(months)
            }
        } catch is CancellationError {
        } catch {
            if state.value == nil { state = .failed(String(describing: error)) }
        }
    }
}

/// "N slips wait to be sent; capture still works" when something is queued.
struct WaitingNote: View {
    let destinations: [Destination]
    let summaries: [UUID: DeliveryQueue.Summary]

    var body: some View {
        let waiting = destinations.filter(\.enabled).reduce(0) { $0 + (summaries[$1.id].map { $0.pending + $0.inFlight } ?? 0) }
        if waiting > 0 {
            Label {
                Text("library.waiting \(waiting)")
            } icon: {
                Image(systemName: "icloud.and.arrow.up").foregroundStyle(EZ.Color.info)
            }
            .font(.footnote)
        }
    }
}

struct LibraryRow: View {
    let item: LibraryItem
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: EZ.Space.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: EZ.Space.sm))
        layout {
            VStack(alignment: .leading, spacing: EZ.Space.xs2) {
                Text(item.slip.merchant ?? String(localized: "review.unknownMerchant"))
                    .foregroundStyle(EZ.Color.text)
                HStack(spacing: EZ.Space.xs) {
                    Text(item.day.date(), format: .dateTime.day().month(.abbreviated))
                    if item.slip.status == .draft { Text("slipStatus.draft").foregroundStyle(EZ.Color.warning) }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: EZ.Space.sm) }
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: EZ.Space.xs2) {
                if let total = item.slip.money(item.slip.total) {
                    Text(total.decimal, format: .currency(code: total.currency))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(EZ.Color.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                DeliveryBadge(state: item.delivery, hasWarnings: item.slip.decodedChecks.contains { $0.severity >= .warning })
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct DeliveryBadge: View {
    let state: DeliveryState
    let hasWarnings: Bool

    var body: some View {
        HStack(spacing: EZ.Space.xs2) {
            if hasWarnings {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(EZ.Color.warning)
                    .accessibilityLabel(Text("library.badge.warnings"))
            }
            switch state {
            case .localOnly: EmptyView()
            case .delivered:
                Image(systemName: "checkmark.icloud").foregroundStyle(EZ.Color.success)
                    .accessibilityLabel(Text("deliveryState.delivered"))
            case .waiting:
                Image(systemName: "icloud.and.arrow.up").foregroundStyle(.secondary)
                    .accessibilityLabel(Text("deliveryState.waiting"))
            case .problem:
                Image(systemName: "exclamationmark.icloud").foregroundStyle(EZ.Color.error)
                    .accessibilityLabel(Text("deliveryState.problem"))
            }
        }
        .font(.footnote)
    }
}

extension LibraryMonth {
    var title: String {
        let date = CalendarDay(year: year, month: month, day: 1)?.date() ?? Date()
        return date.formatted(.dateTime.month(.wide).year())
    }
}
