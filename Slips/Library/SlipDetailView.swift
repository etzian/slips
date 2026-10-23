import PDFKit
import SlipsCore
import SwiftUI

/// One slip: the PDF, its fields, its checks, and where it was delivered, with retry per destination.
struct SlipDetailView: View {
    let slipId: UUID
    @Environment(AppModel.self) private var model
    @State private var slip: Loadable<Slip?> = .loading
    @State private var deliveries: [Delivery] = []
    @State private var destinations: [UUID: Destination] = [:]
    @State private var editing = false
    @State private var error: LocalizedStringKey?

    var body: some View {
        content
            .navigationTitle(Text(verbatim: slip.value??.merchant ?? ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let s = slip.value ?? nil {
                    ShareLink(item: model.files.url(for: s.pdfPath)) { Label("action.share", systemImage: "square.and.arrow.up") }
                    Button("action.edit") { editing = true }
                }
            }
            .sheet(isPresented: $editing) {
                NavigationStack {
                    ReviewView(slipId: slipId) { editing = false }
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { editing = false } } }
                }
            }
            .errorAlert($error)
            .task {
                do {
                    for try await s in model.slips.observeSlip(slipId) { slip = .loaded(s) }
                } catch {
                    slip = .failed(String(describing: error))
                }
            }
            .task {
                if let s = try? model.slips.slip(slipId), let list = try? model.destinations.list(profile: s.profileId) {
                    destinations = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
                }
                for await d in model.deliveries.observeDeliveries(slip: slipId).ignoringErrors() { deliveries = d }
            }
    }

    @ViewBuilder private var content: some View {
        switch slip {
        case .loading:
            SkeletonList(rows: 6)
        case .failed(let detail):
            ErrorStateView(title: "error.load.title", message: "error.load.message", detail: detail, retry: nil)
        case .loaded(nil):
            ContentUnavailableView("error.validation.notFound", systemImage: "doc")
        case .loaded(let s?):
            List {
                Section {
                    PDFKitView(url: model.files.url(for: s.pdfPath))
                        .frame(minHeight: Metrics.pdfPreviewHeight)
                        .listRowInsets(EdgeInsets())
                        .accessibilityLabel(Text("review.thumbnail"))
                }
                ChecksSection(slip: s)
                Section("review.amounts") {
                    amountRow("field.subtotal", s.subtotal, s)
                    amountRow("field.gst", s.gst, s)
                    amountRow("field.qst", s.qst, s)
                    amountRow("field.hst", s.hst, s)
                    amountRow("field.tip", s.tip, s)
                    amountRow("field.total", s.total, s)
                }
                Section("review.details") {
                    if let day = s.txnDate {
                        LabeledContent("field.date") { Text(day.date(), format: .dateTime.year().month().day()) }
                    }
                    if let kind = s.kind { LabeledContent("field.kind") { Text(kind.title) } }
                    if let gst = s.supplierGstNo { LabeledContent("field.gstNumber") { Text(verbatim: gst) } }
                    if let qst = s.supplierQstNo { LabeledContent("field.qstNumber") { Text(verbatim: qst) } }
                    if let notes = s.notes { Text(verbatim: notes) }
                    LabeledContent("field.status") { Text(s.status.title) }
                }
                Section("detail.deliveries") {
                    LabeledContent { Text("destinations.state.library") } label: { Text("destinationType.library") }
                    ForEach(deliveries, id: \.destinationId) { d in
                        DeliveryRow(delivery: d, destination: destinations[d.destinationId]) {
                            attempt($error) { try model.deliveries.retry(slip: d.slipId, destination: d.destinationId) }
                            model.scheduler.trigger("retry")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func amountRow(_ label: LocalizedStringKey, _ value: Int?, _ s: Slip) -> some View {
        if let m = s.money(value) {
            LabeledContent(label) {
                Text(m.decimal, format: .currency(code: m.currency)).monospacedDigit()
            }
        }
    }
}

struct DeliveryRow: View {
    let delivery: Delivery
    let destination: Destination?
    let retry: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: EZ.Space.xs2) {
                Text(verbatim: destination?.name ?? "")
                Text(delivery.status.title)
                    .font(.footnote)
                    .foregroundStyle(delivery.status == .done ? EZ.Color.success
                                     : delivery.status == .failed || delivery.status == .needsAuth ? EZ.Color.error : EZ.Color.textMuted)
            }
            Spacer()
            if delivery.status != .done && delivery.status != .inFlight {
                Button("destinations.retryNow", action: retry)
                    .buttonStyle(.bordered)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The PDF, scrollable and zoomable.
struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}

extension SlipStatus {
    var title: LocalizedStringKey {
        switch self {
        case .draft: "slipStatus.draft"
        case .ready: "slipStatus.ready"
        case .archived: "slipStatus.archived"
        }
    }
}

extension DeliveryStatus {
    var title: LocalizedStringKey {
        switch self {
        case .pending: "deliveryStatus.pending"
        case .inFlight: "deliveryStatus.inFlight"
        case .done: "deliveryStatus.done"
        case .failed: "deliveryStatus.failed"
        case .needsAuth: "deliveryStatus.needsAuth"
        }
    }
}

extension Metrics {
    static let pdfPreviewHeight: CGFloat = 420
}
