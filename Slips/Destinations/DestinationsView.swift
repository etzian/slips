import SlipsCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Destinations: where filed slips go, each with its state and what waits.
struct DestinationsView: View {
    let profileId: UUID
    @Environment(AppModel.self) private var model
    @State private var state: Loadable<[Destination]> = .loading
    @State private var summaries: [UUID: DeliveryQueue.Summary] = [:]
    @State private var pickingFolder = false
    @State private var error: LocalizedStringKey?
    @State private var reload = 0

    var body: some View {
        content
            .navigationTitle(Text("destinations.title"))
            .toolbar {
                Menu {
                    Button { pickingFolder = true } label: { Label("destinations.add.folder", systemImage: "folder") }
                } label: {
                    Label("destinations.add", systemImage: "plus")
                }
            }
            .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
                addFolder(result)
            }
            .errorAlert($error)
            .task(id: reload) {
                do {
                    for try await list in model.destinations.observe(profile: profileId) { state = .loaded(list) }
                } catch {
                    state = .failed(String(describing: error))
                }
            }
            .task(id: reload) {
                for await s in model.deliveries.observeSummaries(profile: profileId).ignoringErrors() { summaries = s }
            }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            SkeletonList(rows: 3)
        case .failed(let detail):
            ErrorStateView(title: "error.load.title", message: "error.load.message", detail: detail) { reload += 1 }
        case .loaded(let destinations):
            List {
                DeliveryBanner(destinations: destinations, summaries: summaries)
                Section {
                    ForEach(destinations) { d in
                        NavigationLink {
                            DestinationDetailView(destination: d)
                        } label: {
                            DestinationRow(destination: d, summary: summaries[d.id])
                        }
                    }
                } footer: {
                    Text("destinations.footer")
                }
            }
        }
    }

    private func addFolder(_ result: Result<URL, any Error>) {
        attempt($error) {
            let url = try result.get()
            let config = try FolderAdapter.config(for: url)
            let d = Destination(profileId: profileId, type: .folder, name: url.lastPathComponent, config: config, enabled: true)
            try model.destinations.save(d)
            model.scheduler.trigger("destination")
        }
    }
}

struct DestinationRow: View {
    let destination: Destination
    let summary: DeliveryQueue.Summary?

    var body: some View {
        HStack(spacing: EZ.Space.sm) {
            Image(systemName: destination.type.symbol)
                .foregroundStyle(.tint)
                .frame(minWidth: Metrics.minTouchTarget / 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: EZ.Space.xs2) {
                Text(destination.name).foregroundStyle(EZ.Color.text)
                DeliveryStateText(destination: destination, summary: summary)
                    .font(.footnote)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One line: off, up to date, how many wait, or what the user must do.
struct DeliveryStateText: View {
    let destination: Destination
    let summary: DeliveryQueue.Summary?

    var body: some View {
        let s = summary ?? DeliveryQueue.Summary()
        if destination.type == .library {
            Text("destinations.state.library").foregroundStyle(.secondary)
        } else if !destination.enabled {
            Text("destinations.state.off").foregroundStyle(.secondary)
        } else if s.needsAuth > 0 {
            Text(destination.type == .folder ? LocalizedStringKey("destinations.state.pickAgain") : "destinations.state.signIn")
                .foregroundStyle(EZ.Color.error)
        } else if s.failed > 0 {
            Text("destinations.state.failed \(s.failed)").foregroundStyle(EZ.Color.error)
        } else if s.pending + s.inFlight > 0 {
            Text("destinations.state.waiting \(s.pending + s.inFlight)").foregroundStyle(EZ.Color.warning)
        } else {
            Text("destinations.state.upToDate").foregroundStyle(.secondary)
        }
    }
}

/// A banner for destinations that need the user: signed out, folder lost, or deliveries given up.
struct DeliveryBanner: View {
    let destinations: [Destination]
    let summaries: [UUID: DeliveryQueue.Summary]

    var body: some View {
        let blocked = destinations.filter { d in
            d.enabled && ((summaries[d.id]?.needsAuth ?? 0) > 0 || (summaries[d.id]?.failed ?? 0) > 0)
        }
        if !blocked.isEmpty {
            Section {
                ForEach(blocked) { d in
                    Label {
                        VStack(alignment: .leading, spacing: EZ.Space.xs2) {
                            Text(d.name).font(.headline)
                            DeliveryStateText(destination: d, summary: summaries[d.id])
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(EZ.Color.error)
                    }
                }
            }
            .listRowBackground(EZ.Color.error.opacity(0.1))
        }
    }
}

extension DestinationType {
    var symbol: String {
        switch self {
        case .library: "iphone"
        case .icloud: "icloud"
        case .folder: "folder"
        case .webdav: "server.rack"
        case .fin: "building.columns"
        case .dropbox, .onedrive, .gdrive: "externaldrive.connected.to.line.below"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .library: "destinationType.library"
        case .icloud: "destinationType.icloud"
        case .folder: "destinationType.folder"
        case .webdav: "destinationType.webdav"
        case .fin: "destinationType.fin"
        case .dropbox: "destinationType.dropbox"
        case .onedrive: "destinationType.onedrive"
        case .gdrive: "destinationType.gdrive"
        }
    }
}

extension AsyncThrowingStream where Element: Sendable {
    /// The values until the first error, which ends the sequence quietly (a banner can wait).
    func ignoringErrors() -> AsyncStream<Element> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    for try await value in self { continuation.yield(value) }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
