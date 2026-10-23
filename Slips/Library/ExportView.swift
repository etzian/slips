import SlipsCore
import SwiftUI

/// Export for a period and the library's filter (or the selection): CSV, JSON, or a ZIP of the PDFs
/// with the CSV. The file is made on the phone and leaves only through the share sheet.
struct ExportView: View {
    let profileId: UUID
    let filter: LibraryFilter
    let only: Set<UUID>?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var from: CalendarDay?
    @State private var to: CalendarDay?
    @State private var format: Format = .zip
    @State private var file: Loadable<URL>?
    @State private var count = 0

    enum Format: String, CaseIterable, Identifiable {
        case csv, json, zip
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .csv: "export.format.csv"
            case .json: "export.format.json"
            case .zip: "export.format.zip"
            }
        }
    }

    init(profileId: UUID, filter: LibraryFilter, only: Set<UUID>?) {
        self.profileId = profileId
        self.filter = filter
        self.only = only
        _from = State(initialValue: filter.from)
        _to = State(initialValue: filter.to)
    }

    var body: some View {
        Form {
            if only == nil {
                Section("library.filter.period") {
                    DayField(day: $from).accessibilityLabel(Text("library.filter.from"))
                    DayField(day: $to).accessibilityLabel(Text("library.filter.to"))
                }
            } else {
                Section { Text("export.selection \(only?.count ?? 0)") }
            }
            Section {
                Picker("export.format", selection: $format) {
                    ForEach(Format.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text("export.footer")
            }
            Section {
                switch file {
                case nil:
                    Button("export.make") { Task { await make() } }
                case .loading?:
                    ProgressView { Text("export.making") }
                case .loaded(let url)?:
                    ShareLink(item: url) { Label("export.share \(count)", systemImage: "square.and.arrow.up") }
                case .failed(let detail)?:
                    ErrorStateView(title: "export.error.title", message: "export.error.message", detail: detail) {
                        Task { await make() }
                    }
                }
            }
        }
        .navigationTitle(Text("library.export"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.done") { dismiss() } } }
        .onChange(of: format) { file = nil }
        .onChange(of: from) { file = nil }
        .onChange(of: to) { file = nil }
    }

    private func make() async {
        file = .loading
        var f = filter
        f.from = from
        f.to = to
        let database = model.database, files = model.files, format = self.format, only = self.only, profileId = self.profileId
        do {
            let (url, n) = try await Task.detached(priority: .userInitiated) { () throws -> (URL, Int) in
                var items = try LibraryQuery(database: database).items(profile: profileId, filter: only == nil ? f : LibraryFilter())
                if let only { items = items.filter { only.contains($0.id) } }
                let exporter = Exporter(database: database, files: files)
                let rows = try exporter.rows(items, localize: catalogLocalize)
                let data: Data
                switch format {
                case .csv: data = Exporter.csv(rows)
                case .json: data = try Exporter.json(rows)
                case .zip: data = try exporter.zip(items, rows: rows)
                }
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let stamp = CalendarDay(Date()).iso
                let url = dir.appendingPathComponent("slips-\(stamp).\(format.rawValue)")
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                return (url, items.count)
            }.value
            count = n
            file = .loaded(url)
        } catch {
            file = .failed(String(describing: error))
        }
    }
}
