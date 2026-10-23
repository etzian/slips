import SlipsCore
import SwiftUI

/// One destination: name, on/off, naming rule with a preview, Wi-Fi only, sidecar, state, retry.
struct DestinationDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var destination: Destination
    @State private var summary = DeliveryQueue.Summary()
    @State private var ruleError: LocalizedStringKey?
    @State private var error: LocalizedStringKey?
    @State private var pickingFolder = false
    @State private var confirmRemove = false
    @State private var removed = false

    init(destination: Destination) {
        _destination = State(initialValue: destination)
    }

    var body: some View {
        Form {
            Section {
                TextField("field.name", text: $destination.name)
                    .onSubmit(save)
                if destination.type != .library {
                    Toggle("destinations.enabled", isOn: $destination.enabled)
                        .onChange(of: destination.enabled) { save() }
                }
                LabeledContent("destinations.type") { Text(destination.type.title) }
            }

            if destination.type != .library {
                Section {
                    LabeledContent("destinations.state") {
                        DeliveryStateText(destination: destination, summary: summary)
                    }
                    if let code = summary.lastErrorCode, summary.failed + summary.needsAuth > 0 {
                        LabeledContent("destinations.lastError") { Text(verbatim: code).font(.footnote.monospaced()) }
                    }
                    Button("destinations.retryNow") {
                        attempt($error) { try model.deliveries.retry(destination: destination.id) }
                        model.scheduler.trigger("retry")
                    }
                    .disabled(summary.waiting == 0)
                    if destination.type == .folder {
                        Button("destinations.pickAgain") { pickingFolder = true }
                    }
                }

                Section {
                    TextField("destinations.namingRule", text: $destination.namingRule, axis: .vertical)
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit(save)
                    if let ruleError {
                        Text(ruleError).font(.footnote).foregroundStyle(EZ.Color.error)
                    }
                    LabeledContent("destinations.preview") {
                        Text(verbatim: preview).font(.footnote.monospaced()).multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("destinations.naming")
                } footer: {
                    Text("destinations.naming.footer")
                }

                Section {
                    Toggle("destinations.wifiOnly", isOn: $destination.wifiOnly)
                        .onChange(of: destination.wifiOnly) { save() }
                    Toggle("destinations.sidecar", isOn: sidecar)
                } footer: {
                    Text("destinations.sidecar.footer")
                }

                Section {
                    Button("destinations.remove", role: .destructive) { confirmRemove = true }
                } footer: {
                    Text("destinations.remove.footer")
                }
            } else {
                Section {
                    Text("destinations.library.explanation")
                }
            }
        }
        .navigationTitle(Text(verbatim: destination.name))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear(perform: save)
        .errorAlert($error)
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            attempt($error) {
                destination.config.merge(try FolderAdapter.config(for: try result.get())) { _, new in new }
                save()
                try model.deliveries.retry(destination: destination.id)
                model.scheduler.trigger("folder")
            }
        }
        .confirmationDialog("destinations.remove.confirm", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("destinations.remove", role: .destructive) {
                attempt($error) {
                    try model.destinations.remove(destination.id)
                    removed = true
                    dismiss()
                }
            }
        }
        .task {
            for await all in model.deliveries.observeSummaries(profile: destination.profileId).ignoringErrors() {
                summary = all[destination.id] ?? DeliveryQueue.Summary()
            }
        }
    }

    private var sidecar: Binding<Bool> {
        Binding {
            destination.keepsSidecar
        } set: { on in
            destination.config[Destination.sidecarKey] = on ? "1" : nil
            save()
        }
    }

    /// The rule applied to a made-up slip, so the user sees what a file will be called.
    private var preview: String {
        var sample = Slip(profileId: destination.profileId, pdfPath: "", pdfSha256: "", pageCount: 1)
        sample.merchant = String(localized: "destinations.preview.merchant")
        sample.txnDate = CalendarDay(Date())
        sample.total = 4367
        sample.kind = .enterprise
        let labels = SlipLabels(business: String(localized: "destinations.preview.business"), subcategoryKey: "enterprise.supplies",
                                paymentMethod: String(localized: "paymentType.creditCard"))
        return NamingRule(destination.namingRule).path(for: sample, labels: labels, localize: catalogLocalize)
    }

    private func save() {
        guard !removed else { return }
        do {
            try model.destinations.save(destination)
            ruleError = nil
            if destination.enabled { model.scheduler.trigger("destination") }
        } catch DestinationError.unknownTokens(let tokens) {
            ruleError = "destinations.naming.unknown \(tokens.joined(separator: ", "))"
        } catch DestinationError.blankName {
            error = "error.validation.blankName"
        } catch {
            AppModel.log.error("destination save failed: \(String(describing: error), privacy: .private)")
            self.error = "error.generic"
        }
    }
}
