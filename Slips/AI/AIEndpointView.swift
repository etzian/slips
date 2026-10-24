import SlipsCore
import SwiftUI

/// Settings › Privacy › Online AI, per profile: off (default), Ollama on the user's network, the
/// Claude API or the OpenAI API. Nothing is sent before the user agrees to exactly what is sent.
struct AIEndpointView: View {
    let profileId: UUID
    @Environment(AppModel.self) private var model
    @State private var settings: AIEndpointSettings?
    @State private var apiKey = ""
    @State private var showConsent = false
    @State private var problem: LocalizedStringKey?
    @State private var error: LocalizedStringKey?

    var body: some View {
        Form {
            if let binding = Binding($settings) {
                content(binding)
            } else {
                SkeletonList(rows: 4)
            }
        }
        .navigationTitle(Text("ai.endpoint.title"))
        .errorAlert($error)
        .sheet(isPresented: $showConsent) {
            if let s = settings {
                NavigationStack { AIConsentView(settings: s) { agreed in finishConsent(agreed) } }
            }
        }
        .task { load() }
        // A new provider or scope is stored at once, so the old consent stops applying right away.
        .onChange(of: settings?.provider) { persistChoice() }
        .onChange(of: settings?.scope) { persistChoice() }
    }

    private func persistChoice() {
        guard let s = settings, let stored = try? model.aiEndpoints.settings(profile: profileId),
              s.provider != stored.provider || s.scope != stored.scope else { return }
        attempt($error) {
            try model.aiEndpoints.save(s)
            settings = try model.aiEndpoints.settings(profile: profileId)
            apiKey = EndpointAssistants.key(settings!) ?? ""
        }
    }

    @ViewBuilder private func content(_ s: Binding<AIEndpointSettings>) -> some View {
        Section {
            Picker("ai.endpoint.provider", selection: s.provider) {
                ForEach(AIProvider.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("ai.endpoint.provider")
        } footer: {
            Text("ai.endpoint.footer")
        }

        if s.wrappedValue.provider == .ollama {
            Section {
                TextField("ai.endpoint.address", text: s.baseUrl.orEmpty)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Toggle("webdav.localNetwork", isOn: s.localNetwork)
                if (s.wrappedValue.baseUrl ?? "").lowercased().hasPrefix("http://") {
                    Label("webdav.plainHTTP.warning", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(EZ.Color.warning)
                }
                if let problem { Text(problem).font(.footnote).foregroundStyle(EZ.Color.error) }
            }
        }

        if s.wrappedValue.provider.needsKey {
            Section {
                SecureField("ai.endpoint.key", text: $apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
            } footer: {
                Text("ai.endpoint.key.footer")
            }
        }

        if s.wrappedValue.provider != .off {
            Section {
                TextField("ai.endpoint.model", text: s.model.orEmpty, prompt: Text(verbatim: s.wrappedValue.provider.defaultModel))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("ai.endpoint.scope", selection: s.scope) {
                    ForEach(AIScope.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }

            Section {
                if s.wrappedValue.hasConsent, let at = s.wrappedValue.consentAt {
                    Label {
                        Text("ai.consent.given \(at.formatted(date: .abbreviated, time: .omitted))")
                    } icon: {
                        Image(systemName: "checkmark.shield").foregroundStyle(EZ.Color.success)
                    }
                } else {
                    Label("ai.consent.missing", systemImage: "hand.raised").foregroundStyle(EZ.Color.warning)
                }
                Button("ai.consent.review") { save(thenConsent: true) }
                    .accessibilityIdentifier("ai.consent.review")
                Button("ai.endpoint.withdraw", role: .destructive) { withdraw() }
            }
        }
    }

    private func load() {
        do {
            let s = try model.aiEndpoints.settings(profile: profileId)
            settings = s
            apiKey = EndpointAssistants.key(s) ?? ""
        } catch {
            self.error = "error.generic"
        }
    }

    /// Saves (a change of provider or scope drops the consent), then opens the consent screen.
    private func save(thenConsent: Bool) {
        guard var s = settings else { return }
        if s.provider == .ollama {
            switch WebDAVConfig.validate(base: s.baseUrl ?? "", localNetwork: s.localNetwork) {
            case .failure(.insecure): problem = "webdav.problem.insecure"; return
            case .failure(.notAURL): problem = "webdav.problem.notAURL"; return
            case .success: problem = nil
            }
        }
        if s.provider.needsKey && apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
            error = "ai.endpoint.key.missing"
            return
        }
        s.model = s.model?.trimmingCharacters(in: .whitespaces).isEmpty == true ? nil : s.model
        attempt($error) {
            if s.provider.needsKey {
                try Keychain.set(apiKey.trimmingCharacters(in: .whitespaces),
                                 account: Keychain.aiAccount(profile: profileId, provider: s.provider.rawValue))
            }
            try model.aiEndpoints.save(s)
            settings = try model.aiEndpoints.settings(profile: profileId)
            if thenConsent { showConsent = true }
        }
    }

    private func finishConsent(_ agreed: Bool) {
        showConsent = false
        guard agreed else { return }
        attempt($error) {
            try model.aiEndpoints.consent(profile: profileId)
            settings = try model.aiEndpoints.settings(profile: profileId)
        }
    }

    /// Off, consent gone, every key of this profile forgotten.
    private func withdraw() {
        attempt($error) {
            try model.aiEndpoints.withdraw(profile: profileId)
            Keychain.deleteAIKeys(profile: profileId)
            apiKey = ""
            settings = try model.aiEndpoints.settings(profile: profileId)
        }
    }
}

/// What is sent, to whom, and when — with the real text of the profile's latest slip as it would go,
/// card digits masked. Agreeing stores the consent for exactly these settings.
struct AIConsentView: View {
    let settings: AIEndpointSettings
    let done: (Bool) -> Void
    @Environment(AppModel.self) private var model
    @State private var sample: String?

    var body: some View {
        List {
            Section("ai.consent.who") {
                Text(settings.provider.recipient)
            }
            Section("ai.consent.when") {
                Text(settings.scope == .everySlip ? LocalizedStringKey("ai.consent.when.every") : "ai.consent.when.onRequest")
            }
            Section {
                Text("ai.consent.what")
                if let sample {
                    Text(verbatim: sample)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .accessibilityLabel(Text("ai.consent.sample"))
                }
            } header: {
                Text("ai.consent.whatHeader")
            }
            Section("ai.consent.never") {
                Label("ai.consent.never.image", systemImage: "photo")
                Label("ai.consent.never.card", systemImage: "creditcard")
                Label("ai.consent.never.names", systemImage: "person.crop.circle")
            }
            if settings.provider.isThirdParty {
                Section {
                    Text("ai.consent.outsideQuebec")
                }
            }
            Section {
                Button {
                    done(true)
                } label: {
                    Text("ai.consent.agree").frame(maxWidth: .infinity, minHeight: Metrics.minTouchTarget)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("ai.consent.agree")
                Button {
                    done(false)
                } label: {
                    Text("ai.consent.decline").frame(maxWidth: .infinity, minHeight: Metrics.minTouchTarget)
                }
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle(Text("ai.consent.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // The latest slip of this profile, exactly as it would be sent.
            let items = try? LibraryQuery(database: model.database).items(profile: settings.profileId, filter: LibraryFilter())
            sample = items?.lazy.compactMap { AIPrivacy.input(for: $0.slip, locale: Locale.current.identifier)?.ocrText }.first
        }
    }
}
