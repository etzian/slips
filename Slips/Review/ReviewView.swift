import PDFKit
import SlipsCore
import SwiftUI

/// After capture: the slip's thumbnail, the extracted fields (editable, low confidence marked) and the
/// pickers. Save files the slip and queues its deliveries; Save as draft keeps it here.
struct ReviewView: View {
    let slipId: UUID
    /// What Cancel does: right after a capture it discards the new draft; when editing, it closes.
    var cancel: CancelAction = .close
    let onDone: () -> Void

    enum CancelAction { case discardCapture, close }

    @Environment(AppModel.self) private var model
    @State private var state: Loadable<Slip> = .loading
    @State private var draft: Slip?
    @State private var reference = ReferenceSnapshot()
    @State private var profiles: [Profile] = []
    @State private var error: LocalizedStringKey?
    @State private var reload = 0
    @State private var newPaymentMethod: PaymentMethod?
    @State private var confirmDiscard = false

    var body: some View {
        Group {
            switch state {
            case .loading:
                SkeletonList(rows: 8)
            case .failed(let detail):
                ErrorStateView(title: "error.load.title", message: "error.load.message", detail: detail) { reload += 1 }
            case .loaded:
                if let binding = Binding($draft) { form(binding) }
            }
        }
        .navigationTitle(Text("review.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let slip = draft {
                ShareLink(item: model.files.url(for: slip.pdfPath)) {
                    Label("action.share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .errorAlert($error)
        .task(id: reload) { load() }
        .onChange(of: draft) { _, edited in
            // Checks follow every edit.
            guard var slip = edited, let checks = try? model.slips.checks(for: slip) else { return }
            slip.setChecks(checks)
            if slip != edited { draft = slip }
        }
        .confirmationDialog("review.discard.title", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("review.discard.action", role: .destructive) {
                attempt($error) {
                    try model.slips.discardDraft(slipId)
                    onDone()
                }
            }
            Button("review.discard.keepDraft") { onDone() }
        } message: {
            Text("review.discard.message")
        }
        .sheet(item: $newPaymentMethod, onDismiss: refreshReference) { method in
            NavigationStack { PaymentMethodEditor(method: method) }
        }
    }

    private func form(_ slip: Binding<Slip>) -> some View {
        Form {
            Section {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: EZ.Space.md) { summary(slip.wrappedValue) }
                    VStack(alignment: .leading, spacing: EZ.Space.md) { summary(slip.wrappedValue) }
                }
            }
            .accessibilityElement(children: .combine)

            ChecksSection(slip: slip.wrappedValue) { last4 in
                newPaymentMethod = PaymentMethod(profileId: slip.wrappedValue.profileId, name: "", type: .creditCard, last4: last4,
                                                 currency: slip.wrappedValue.currency)
            }

            Section("review.classification") {
                Picker("field.profile", selection: profileBinding(slip)) {
                    ForEach(profiles) { Text($0.name).tag($0.id) }
                }
                Picker("field.kind", selection: kindBinding(slip)) {
                    Text("value.choose").tag(Kind?.none)
                    ForEach(Kind.allCases, id: \.self) { Text($0.title).tag(Kind?.some($0)) }
                }
                .accessibilityIdentifier("review.kind")
                if slip.wrappedValue.kind == .enterprise {
                    Picker("field.business", selection: slip.enterpriseId) {
                        Text("value.choose").tag(UUID?.none)
                        ForEach(reference.enterprises) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }
                Picker("field.subcategory", selection: slip.subcategoryId) {
                    Text("value.choose").tag(UUID?.none)
                    if let kind = slip.wrappedValue.kind {
                        ForEach(reference.subcategories(for: kind)) { Text($0.displayName).tag(UUID?.some($0.id)) }
                    }
                }
                .disabled(slip.wrappedValue.kind == nil)
                .accessibilityIdentifier("review.subcategory")
                Picker("field.paymentMethod", selection: slip.paymentMethodId) {
                    Text("value.none").tag(UUID?.none)
                    ForEach(reference.paymentMethods) { m in
                        Text(m.last4.map { "\(m.name) ····\($0)" } ?? m.name).tag(UUID?.some(m.id))
                    }
                }
            }

            Section("review.details") {
                FieldRow(label: "field.merchant", low: low(\.merchant)) {
                    TextField("field.merchant", text: slip.merchant.orEmpty)
                }
                FieldRow(label: "field.date", low: low(\.date)) {
                    DayField(day: slip.txnDate)
                }
                FieldRow(label: "field.currency", low: low(\.currency)) {
                    TextField("field.currency", text: slip.currency)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
            }

            Section("review.amounts") {
                amount("field.subtotal", slip.subtotal, low(\.subtotal), slip.wrappedValue.currency)
                amount("field.gst", slip.gst, low(\.gst), slip.wrappedValue.currency)
                amount("field.qst", slip.qst, low(\.qst), slip.wrappedValue.currency)
                amount("field.hst", slip.hst, low(\.hst), slip.wrappedValue.currency)
                amount("field.tip", slip.tip, low(\.tip), slip.wrappedValue.currency)
                amount("field.total", slip.total, low(\.total), slip.wrappedValue.currency)
            }

            Section("review.registration") {
                FieldRow(label: "field.gstNumber", low: low(\.supplierGstNo)) {
                    TextField("field.gstNumber", text: slip.supplierGstNo.orEmpty)
                }
                FieldRow(label: "field.qstNumber", low: low(\.supplierQstNo)) {
                    TextField("field.qstNumber", text: slip.supplierQstNo.orEmpty)
                }
            }

            Section("field.notes") {
                TextField("field.notes", text: slip.notes.orEmpty, axis: .vertical)
                    .lineLimit(2...6)
            }

            Section {
                Button {
                    save(slip.wrappedValue, ready: true)
                } label: {
                    Text("review.save").frame(maxWidth: .infinity, minHeight: Metrics.minTouchTarget)
                }
                .buttonStyle(.borderedProminent)
                .disabled(slip.wrappedValue.decodedChecks.contains { $0.severity == .blocking })
                .accessibilityIdentifier("review.save")
                Button {
                    save(slip.wrappedValue, ready: false)
                } label: {
                    Text("review.saveDraft").frame(maxWidth: .infinity, minHeight: Metrics.minTouchTarget)
                }
                .accessibilityIdentifier("review.saveDraft")
                Button(role: cancel == .discardCapture ? .destructive : nil) {
                    if cancel == .discardCapture { confirmDiscard = true } else { onDone() }
                } label: {
                    Text("action.cancel").frame(maxWidth: .infinity, minHeight: Metrics.minTouchTarget)
                }
                .accessibilityIdentifier("review.cancel")
            }
            .listRowBackground(Color.clear)
        }
    }

    /// Thumbnail, merchant, total and page count; side by side, or stacked at large text sizes.
    @ViewBuilder private func summary(_ slip: Slip) -> some View {
        PDFThumbnail(url: model.files.url(for: slip.pdfPath))
        VStack(alignment: .leading, spacing: EZ.Space.xs) {
            Text(slip.merchant ?? String(localized: "review.unknownMerchant"))
                .font(.headline)
            if let total = slip.money(slip.total) {
                Text(total.decimal, format: .currency(code: total.currency))
                    .font(.title3.monospacedDigit())
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("review.pages \(slip.pageCount)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func amount(_ label: LocalizedStringKey, _ value: Binding<Int?>, _ low: Bool, _ currency: String) -> some View {
        FieldRow(label: label, low: low) {
            MoneyField(label: label, minorUnits: value, currency: currency)
        }
    }

    private func low<V>(_ field: KeyPath<Extraction, ExtractedField<V>?>) -> Bool {
        draft?.extraction?[keyPath: field]?.isLowConfidence ?? false
    }

    // MARK: Pickers that depend on each other

    private func profileBinding(_ slip: Binding<Slip>) -> Binding<UUID> {
        Binding {
            slip.wrappedValue.profileId
        } set: { id in
            guard id != slip.wrappedValue.profileId else { return }
            slip.wrappedValue.profileId = id
            slip.wrappedValue.enterpriseId = nil
            slip.wrappedValue.subcategoryId = nil
            slip.wrappedValue.paymentMethodId = nil
            reference = (try? model.reference.snapshot(profile: id)) ?? ReferenceSnapshot()
        }
    }

    private func kindBinding(_ slip: Binding<Slip>) -> Binding<Kind?> {
        Binding {
            slip.wrappedValue.kind
        } set: { kind in
            slip.wrappedValue.kind = kind
            if kind != .enterprise { slip.wrappedValue.enterpriseId = nil }
            if let kind, let sub = slip.wrappedValue.subcategoryId,
               !reference.subcategories(for: kind).contains(where: { $0.id == sub }) {
                slip.wrappedValue.subcategoryId = nil
            }
        }
    }

    // MARK: Load and save

    /// After a payment method was created from a check: reload the pickers and pick the new card.
    private func refreshReference() {
        guard var slip = draft else { return }
        reference = (try? model.reference.snapshot(profile: slip.profileId)) ?? reference
        if slip.paymentMethodId == nil, let last4 = slip.extraction?.cardLast4?.value,
           let method = reference.paymentMethods.first(where: { $0.last4 == last4 }) {
            slip.paymentMethodId = method.id
            if slip.kind == nil { slip.kind = method.defaultKind }
            draft = slip
        }
    }

    private func load() {
        do {
            guard var slip = try model.slips.slip(slipId) else {
                state = .failed(String(localized: "error.validation.notFound"))
                return
            }
            profiles = try model.database.profiles()
            reference = try model.reference.snapshot(profile: slip.profileId)
            if slip.kind == nil && slip.subcategoryId == nil && slip.paymentMethodId == nil {
                let s = try model.slips.suggestion(for: slip)
                slip.kind = s.kind
                slip.enterpriseId = s.enterpriseId
                slip.subcategoryId = s.subcategoryId
                slip.paymentMethodId = s.paymentMethodId
            }
            slip.setChecks(try model.slips.checks(for: slip))
            draft = slip
            state = .loaded(slip)
        } catch {
            state = .failed(String(describing: error))
        }
    }

    private func save(_ slip: Slip, ready: Bool) {
        do {
            var s = slip
            s.currency = s.currency.trimmingCharacters(in: .whitespaces).uppercased()
            if ready {
                try model.slips.markReady(s)
                model.scheduler.trigger("save")
            } else {
                try model.slips.saveDraft(s)
            }
            onDone()
        } catch SaveError.classificationIncomplete {
            error = "error.save.incomplete"
        } catch SaveError.blockingCheck {
            error = "error.save.blocking"
        } catch {
            AppModel.log.error("save failed: \(String(describing: error), privacy: .private)")
            self.error = "error.generic"
        }
    }
}

/// A labelled field; a low-confidence value gets a warning mark and a spoken hint.
struct FieldRow<Content: View>: View {
    let label: LocalizedStringKey
    let low: Bool
    @ViewBuilder let content: Content

    var body: some View {
        LabeledContent {
            content.multilineTextAlignment(.trailing)
        } label: {
            HStack(spacing: EZ.Space.xs2) {
                Text(label)
                if low {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(EZ.Color.warning)
                        .accessibilityLabel(Text("review.lowConfidence"))
                }
            }
        }
        .listRowBackground(low ? EZ.Color.warning.opacity(0.12) : nil)
        .accessibilityHint(low ? Text("review.lowConfidence.hint") : Text(verbatim: ""))
    }
}

/// An amount in minor units, typed and shown with the slip's currency format.
struct MoneyField: View {
    let label: LocalizedStringKey
    @Binding var minorUnits: Int?
    let currency: String

    var body: some View {
        TextField(label, value: decimal, format: .currency(code: currency.count == 3 ? currency : "CAD"))
            .keyboardType(.decimalPad)
            .font(.body.monospacedDigit())
    }

    private var decimal: Binding<Decimal?> {
        Binding {
            minorUnits.map { Money(minorUnits: $0, currency: currency).decimal }
        } set: { value in
            minorUnits = value.map { Money.minorUnits(from: $0, currency: currency) }
        }
    }
}

/// A slip's calendar day, or a button to add one.
struct DayField: View {
    @Binding var day: CalendarDay?

    var body: some View {
        if let current = day {
            HStack {
                DatePicker("field.date", selection: Binding {
                    current.date()
                } set: {
                    day = CalendarDay($0)
                }, displayedComponents: .date)
                .labelsHidden()
                Button {
                    day = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        .frame(minWidth: Metrics.minTouchTarget, minHeight: Metrics.minTouchTarget)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("review.clearDate"))
            }
        } else {
            Button("review.addDate") { day = CalendarDay(Date()) }
                .buttonStyle(.borderless)
        }
    }
}

/// The first page of the slip's PDF, small.
struct PDFThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "doc").font(.largeTitle).foregroundStyle(.secondary)
            }
        }
        .frame(width: Metrics.thumbnailWidth, height: Metrics.thumbnailWidth * 1.4)
        .background(EZ.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: EZ.Radius.sm))
        .accessibilityLabel(Text("review.thumbnail"))
        .task(id: url) {
            let url = self.url
            image = await Task.detached {
                PDFDocument(url: url)?.page(at: 0)?.thumbnail(of: CGSize(width: 240, height: 336), for: .mediaBox)
            }.value
        }
    }
}

extension Binding where Value == String? {
    /// An optional string edited as a plain one: empty means nil.
    var orEmpty: Binding<String> {
        Binding<String> {
            wrappedValue ?? ""
        } set: {
            wrappedValue = $0.isEmpty ? nil : $0
        }
    }
}
