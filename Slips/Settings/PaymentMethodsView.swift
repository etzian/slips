import SlipsCore
import SwiftUI

/// Payment methods: name, type, last four, currency, default kind and business.
struct PaymentMethodsView: View {
    let profileId: UUID
    @Environment(AppModel.self) private var model
    @State private var state: Loadable<[PaymentMethod]> = .loading
    @State private var editing: PaymentMethod?
    @State private var error: LocalizedStringKey?
    @State private var notice: LocalizedStringKey?
    @State private var reload = 0

    var body: some View {
        content
            .navigationTitle(Text("paymentMethods.title"))
            .toolbar {
                Button { add() } label: { Label("paymentMethods.new", systemImage: "plus") }
            }
            .sheet(item: $editing) { method in
                NavigationStack { PaymentMethodEditor(method: method) }
            }
            .errorAlert($error)
            .safeAreaInset(edge: .bottom) { NoticeBanner(text: $notice) }
            .task(id: reload) {
                do {
                    for try await list in model.reference.observePaymentMethods(profile: profileId) { state = .loaded(list) }
                } catch {
                    state = .failed(String(describing: error))
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            SkeletonList(rows: 3)
        case .failed(let detail):
            ErrorStateView(title: "error.load.title", message: "error.load.message", detail: detail) { reload += 1 }
        case .loaded(let items) where items.isEmpty:
            ContentUnavailableView {
                Label("paymentMethods.empty.title", systemImage: "creditcard")
            } description: {
                Text("paymentMethods.empty.message")
            } actions: {
                Button("paymentMethods.new") { add() }.buttonStyle(.borderedProminent)
            }
        case .loaded(let items):
            List {
                Section {
                    ForEach(items.filter { $0.archivedAt == nil }) { m in
                        Button { editing = m } label: { PaymentMethodRow(method: m) }
                            .swipeActions {
                                Button("action.remove", role: .destructive) { remove(m) }
                            }
                    }
                }
                let archived = items.filter { $0.archivedAt != nil }
                if !archived.isEmpty {
                    Section("section.archived") {
                        ForEach(archived) { m in
                            PaymentMethodRow(method: m)
                                .foregroundStyle(.secondary)
                                .swipeActions {
                                    Button("action.restore") {
                                        attempt($error) { try model.reference.unarchivePaymentMethod(m.id) }
                                    }.tint(EZ.Color.accent)
                                }
                        }
                    }
                }
            }
        }
    }

    private func add() {
        editing = PaymentMethod(profileId: profileId, name: "", type: .creditCard)
    }

    private func remove(_ m: PaymentMethod) {
        attempt($error) {
            if try model.reference.removePaymentMethod(m.id) == .archived { notice = "notice.archivedInUse" }
        }
    }
}

struct PaymentMethodRow: View {
    let method: PaymentMethod

    var body: some View {
        VStack(alignment: .leading, spacing: EZ.Space.xs2) {
            Text(method.name).foregroundStyle(EZ.Color.text)
            HStack(spacing: EZ.Space.xs) {
                Text(method.type.title)
                if let last4 = method.last4 {
                    Text("paymentMethods.endingIn \(last4)")
                }
                Text(verbatim: method.currency)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct PaymentMethodEditor: View {
    @State var method: PaymentMethod
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var last4 = ""
    @State private var enterprises: [Enterprise] = []
    @State private var fieldError: ValidationError?
    @State private var error: LocalizedStringKey?

    init(method: PaymentMethod) {
        _method = State(initialValue: method)
        _last4 = State(initialValue: method.last4 ?? "")
    }

    var body: some View {
        Form {
            Section {
                TextField("field.name", text: $method.name)
                    .textInputAutocapitalization(.words)
                if fieldError == .blankName { fieldMessage(.blankName) }
                Picker("field.paymentType", selection: $method.type) {
                    ForEach(PaymentType.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("field.lastFour", text: $last4)
                    .keyboardType(.numberPad)
                    .onChange(of: last4) { _, new in last4 = String(new.filter(\.isNumber).prefix(4)) }
                if fieldError == .invalidLastFour { fieldMessage(.invalidLastFour) }
                TextField("field.currency", text: $method.currency)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                if fieldError == .invalidCurrency { fieldMessage(.invalidCurrency) }
            }
            Section {
                Picker("field.defaultKind", selection: $method.defaultKind) {
                    Text("value.none").tag(Kind?.none)
                    ForEach(Kind.allCases, id: \.self) { Text($0.title).tag(Kind?.some($0)) }
                }
                if method.defaultKind == .enterprise {
                    Picker("field.defaultBusiness", selection: $method.defaultEnterpriseId) {
                        Text("value.none").tag(UUID?.none)
                        ForEach(enterprises) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }
            } footer: {
                Text("paymentMethods.defaults.footer")
            }
        }
        .navigationTitle(Text(method.name.isEmpty ? LocalizedStringKey("paymentMethods.new") : "paymentMethods.edit"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("action.save") { save() } }
        }
        .errorAlert($error)
        .task {
            enterprises = (try? model.reference.snapshot(profile: method.profileId).enterprises) ?? []
        }
    }

    private func fieldMessage(_ e: ValidationError) -> some View {
        Text(e.message)
            .font(.footnote)
            .foregroundStyle(EZ.Color.error)
    }

    private func save() {
        method.last4 = last4.isEmpty ? nil : last4
        do {
            try model.reference.savePaymentMethod(method)
            dismiss()
        } catch let e as ValidationError {
            fieldError = e
        } catch {
            self.error = "error.generic"
        }
    }
}
