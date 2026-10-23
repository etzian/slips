import SlipsCore
import SwiftUI

/// The slip's open checks, most severe first. Hidden when there are none. An unknown card offers to
/// create the payment method.
struct ChecksSection: View {
    let slip: Slip
    var createPaymentMethod: ((String) -> Void)?

    var body: some View {
        let checks = slip.decodedChecks.sorted { $0.severity > $1.severity }
        if !checks.isEmpty {
            Section("review.checks") {
                ForEach(checks, id: \.self) { check in
                    CheckRow(check: check)
                    if check.code == SlipChecks.Code.cardUnknown, case .text(let last4)? = check.values.first,
                       let createPaymentMethod {
                        Button("review.createPaymentMethod") { createPaymentMethod(last4) }
                    }
                }
            }
        }
    }
}

struct CheckRow: View {
    let check: Check

    var body: some View {
        Label {
            Text(check.message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: check.severity.symbol).foregroundStyle(check.severity.color)
        }
        .accessibilityLabel(Text(check.severity.title) + Text(verbatim: ": ") + Text(check.message))
    }
}

extension CheckSeverity {
    var symbol: String {
        switch self {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .blocking: "xmark.octagon"
        }
    }

    var color: Color {
        switch self {
        case .info: EZ.Color.info
        case .warning: EZ.Color.warning
        case .blocking: EZ.Color.error
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .info: "check.severity.info"
        case .warning: "check.severity.warning"
        case .blocking: "check.severity.blocking"
        }
    }
}

extension Check {
    /// The translated message of `check.<code>`, its `%@` placeholders filled with `values` in order,
    /// each formatted for the user's locale.
    var message: String {
        let format = Bundle.main.localizedString(forKey: "check.\(code)", value: code, table: nil)
        let args = values.map(\.formatted)
        return args.isEmpty ? format : String(format: format, locale: .current, arguments: args.map { $0 as CVarArg })
    }
}

extension CheckValue {
    var formatted: String {
        switch self {
        case .money(let minor, let currency):
            Money(minorUnits: minor, currency: currency).decimal.formatted(.currency(code: currency))
        case .day(let day):
            day.date().formatted(date: .abbreviated, time: .omitted)
        case .text(let text):
            text
        case .number(let n):
            n.formatted()
        }
    }
}
