import SlipsCore
import SwiftUI

/// The slip's open checks, most severe first. Hidden when there are none.
struct ChecksSection: View {
    let slip: Slip

    var body: some View {
        let checks = slip.decodedChecks.sorted { $0.severity > $1.severity }
        if !checks.isEmpty {
            Section("review.checks") {
                ForEach(checks, id: \.self) { CheckRow(check: $0) }
            }
        }
    }
}

struct CheckRow: View {
    let check: Check

    var body: some View {
        Label {
            Text(check.message)
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
    /// The translated message of `check.<code>`, its placeholders filled with `values` in order.
    var message: String {
        let format = Bundle.main.localizedString(forKey: "check.\(code)", value: code, table: nil)
        return values.isEmpty ? format : String(format: format, arguments: values.map { $0 as CVarArg })
    }
}
