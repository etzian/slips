import Foundation
import SlipsCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether Apple's on-device model can run here, and why not.
enum OnDeviceStatus: Equatable {
    case available
    case needsNewerIOS
    case deviceNotEligible
    case notEnabled
    case notReady
    case unavailable

    var message: String {
        switch self {
        case .available: String(localized: "ai.onDevice.status.available")
        case .needsNewerIOS: String(localized: "ai.onDevice.status.needsNewerIOS")
        case .deviceNotEligible: String(localized: "ai.onDevice.status.deviceNotEligible")
        case .notEnabled: String(localized: "ai.onDevice.status.notEnabled")
        case .notReady: String(localized: "ai.onDevice.status.notReady")
        case .unavailable: String(localized: "ai.onDevice.status.unavailable")
        }
    }
}

/// The on-device model (Foundation Models, iOS 26, Apple Intelligence). On by default: nothing leaves
/// the phone. Unavailable for any reason = no assistant, and the app works as without AI.
enum OnDeviceAI {
    static let settingKey = "aiOnDevice"
    static let timeout: Duration = .seconds(30)

    /// The user's switch; on unless turned off.
    static var isOn: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }

    static var status: OnDeviceStatus {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .available
            case .unavailable(.deviceNotEligible): return .deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled): return .notEnabled
            case .unavailable(.modelNotReady): return .notReady
            case .unavailable: return .unavailable
            }
        }
        #endif
        return .needsNewerIOS
    }

    /// The assistant to run after OCR, or nil when it is off or cannot run.
    static func assistant() -> (any ExtractionAssistant)? {
        guard isOn, status == .available else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return OnDeviceAssistant() }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
/// The answer shape the on-device model generates (guided generation). Amounts as printed text; the
/// core turns them into minor units.
@available(iOS 26.0, *)
@Generable
struct GeneratedSlipReading {
    @Guide(description: "Store or company name as printed, or nil")
    var merchant: String?
    @Guide(description: "Transaction date as YYYY-MM-DD, or nil")
    var date: String?
    @Guide(description: "Subtotal before taxes, digits with a dot for decimals, or nil")
    var subtotal: String?
    @Guide(description: "GST / TPS amount, or nil")
    var gst: String?
    @Guide(description: "QST / TVQ amount, or nil")
    var qst: String?
    @Guide(description: "HST / TVH amount, or nil")
    var hst: String?
    @Guide(description: "Tip / pourboire amount, or nil")
    var tip: String?
    @Guide(description: "Total paid including tip, or nil")
    var total: String?
    @Guide(description: "ISO 4217 currency code such as CAD or USD, or nil")
    var currency: String?
    @Guide(description: "Supplier GST number such as 123456789 RT0001, or nil")
    var supplierGstNo: String?
    @Guide(description: "Supplier QST number such as 1234567890 TQ0001, or nil")
    var supplierQstNo: String?
    @Guide(description: "One sub-category key from the list in the instructions, or nil")
    var subcategoryKey: String?
}

@available(iOS 26.0, *)
struct OnDeviceAssistant: ExtractionAssistant {
    let id = "on_device"

    func extract(_ input: AssistantInput) async throws -> AIExtraction {
        let session = LanguageModelSession(instructions: AssistantPrompt.instructions)
        let response = try await session.respond(to: AssistantPrompt.message(input), generating: GeneratedSlipReading.self)
        let r = response.content
        func number(_ s: String?) -> Decimal? { s.flatMap(AssistantReading.decimal(from:)) }
        let reading = AssistantReading(merchant: r.merchant, date: r.date, subtotal: number(r.subtotal), gst: number(r.gst),
                                       qst: number(r.qst), hst: number(r.hst), tip: number(r.tip), total: number(r.total),
                                       currency: r.currency?.uppercased(), supplierGstNo: r.supplierGstNo,
                                       supplierQstNo: r.supplierQstNo, subcategoryKey: r.subcategoryKey)
        return reading.extraction(fallbackCurrency: input.currencyHint ?? "CAD")
    }
}
#endif

/// Runs an assistant with a time limit; a slow model never holds anything up.
func withTimeout<T: Sendable>(_ limit: Duration, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: limit)
            throw CancellationError()
        }
        let first = try await group.next()!
        group.cancelAll()
        return first
    }
}
