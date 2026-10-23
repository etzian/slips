import SlipsCore
import SwiftUI

/// Adds a WebDAV server (a NAS, Nextcloud, a WebDAV container): address, user, password (Keychain),
/// optional health URL, and whether the host is on the local network (plain HTTP allowed only then).
struct WebDAVSetupView: View {
    let profileId: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = "https://"
    @State private var username = ""
    @State private var password = ""
    @State private var health = ""
    @State private var localNetwork = false
    @State private var problem: LocalizedStringKey?
    @State private var testing = false
    @State private var testResult: LocalizedStringKey?
    @State private var error: LocalizedStringKey?

    var body: some View {
        Form {
            Section {
                TextField("field.name", text: $name)
                TextField("webdav.address", text: $address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let problem { Text(problem).font(.footnote).foregroundStyle(EZ.Color.error) }
                Toggle("webdav.localNetwork", isOn: $localNetwork)
                if isPlainHTTP {
                    Label("webdav.plainHTTP.warning", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(EZ.Color.warning)
                }
            } footer: {
                Text("webdav.localNetwork.footer")
            }
            Section {
                TextField("webdav.username", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("webdav.password", text: $password)
                    .textContentType(.password)
            } footer: {
                Text("webdav.password.footer")
            }
            Section {
                TextField("webdav.health", text: $health)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text("webdav.health.footer")
            }
            Section {
                Button {
                    Task { await test() }
                } label: {
                    HStack {
                        Text("webdav.test")
                        if testing { Spacer(); ProgressView() }
                    }
                }
                .disabled(testing)
                if let testResult { Text(testResult).font(.footnote) }
            }
        }
        .navigationTitle(Text("destinationType.webdav"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("action.save") { save() }
            }
        }
        .errorAlert($error)
    }

    /// An `http://` address: the password and the slips cross the network unencrypted.
    private var isPlainHTTP: Bool {
        address.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("http://")
    }

    private func config() -> WebDAVConfig? {
        switch WebDAVConfig.validate(base: address, localNetwork: localNetwork) {
        case .failure(.insecure):
            problem = "webdav.problem.insecure"
            return nil
        case .failure(.notAURL):
            problem = "webdav.problem.notAURL"
            return nil
        case .success(let url):
            problem = nil
            let healthURL = health.trimmingCharacters(in: .whitespaces).isEmpty ? nil : URL(string: health.trimmingCharacters(in: .whitespaces))
            return WebDAVConfig(baseURL: url, username: username.trimmingCharacters(in: .whitespaces), password: password,
                                healthURL: healthURL, localNetwork: localNetwork)
        }
    }

    private func test() async {
        guard let config = config() else { return }
        testing = true
        defer { testing = false }
        switch await WebDAVClient(config: config, transport: AppHTTPTransport()).probe() {
        case .reachable: testResult = "webdav.test.ok"
        case .needsAuth: testResult = "webdav.test.auth"
        case .unreachable: testResult = "webdav.test.unreachable"
        }
    }

    private func save() {
        guard let config = config() else { return }
        let title = name.trimmingCharacters(in: .whitespaces).isEmpty ? (config.baseURL.host ?? "WebDAV") : name
        let destination = Destination(profileId: profileId, type: .webdav, name: title, config: config.config, enabled: true)
        attempt($error) {
            try Keychain.set(password, for: destination.id)
            do {
                try model.destinations.save(destination)
            } catch {
                Keychain.delete(destination.id)
                throw error
            }
            model.scheduler.trigger("destination")
            dismiss()
        }
    }
}
