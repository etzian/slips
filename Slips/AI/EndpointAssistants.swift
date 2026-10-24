import Foundation
import SlipsCore

/// Builds the endpoint adapter for a profile's consented settings (M2 P5–P7). The router has already
/// checked consent and scope; a provider without an adapter yet returns nil, so nothing is sent.
enum EndpointAssistants {
    @Sendable static func make(_ settings: AIEndpointSettings) -> (any ExtractionAssistant)? {
        switch settings.provider {
        case .off, .ollama, .claude, .openai:
            nil
        }
    }

    /// The key saved for this profile and provider, if the provider needs one.
    static func key(_ settings: AIEndpointSettings) -> String? {
        Keychain.get(account: Keychain.aiAccount(profile: settings.profileId, provider: settings.provider.rawValue))
    }

    /// Runs an endpoint on a slip and records the reading. Errors are logged privately and dropped: a
    /// model never blocks a slip.
    static func run(_ assistant: any ExtractionAssistant, on slip: Slip, slips: SlipStore) async {
        guard let input = AIPrivacy.input(for: slip, reference: slip.txnDate, locale: Locale.current.identifier) else { return }
        do {
            let reading = try await withTimeout(.seconds(60)) { try await assistant.extract(input) }
            try slips.recordAI(reading, assistant: assistant.id, for: slip.id)
        } catch {
            AppModel.log.notice("endpoint AI skipped: \(String(describing: error), privacy: .private)")
        }
    }
}

extension AIProvider {
    var title: LocalizedStringResource {
        switch self {
        case .off: "ai.provider.off"
        case .ollama: "ai.provider.ollama"
        case .claude: "ai.provider.claude"
        case .openai: "ai.provider.openai"
        }
    }

    /// Who receives the text, and where.
    var recipient: LocalizedStringResource {
        switch self {
        case .off: "ai.recipient.none"
        case .ollama: "ai.recipient.ollama"
        case .claude: "ai.recipient.claude"
        case .openai: "ai.recipient.openai"
        }
    }

    /// The model used when the user does not name one (P8 records the choice).
    var defaultModel: String {
        switch self {
        case .off: ""
        case .ollama: "llama3.2"
        case .claude: "claude-haiku-5-5"
        case .openai: "gpt-5-mini"
        }
    }
}

extension AIScope {
    var title: LocalizedStringResource {
        switch self {
        case .onRequest: "ai.scope.onRequest"
        case .everySlip: "ai.scope.everySlip"
        }
    }
}
