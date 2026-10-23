import SlipsCore
import SwiftUI

/// Where a screen's data stands. Every list goes through these states (GUIDELINES §4).
enum Loadable<Value> {
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case .loaded(let v) = self { return v }
        return nil
    }
}

/// The error state: what happened, what it means, one recovery action, and the technical detail
/// behind a disclosure.
struct ErrorStateView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let detail: String
    let retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: EZ.Space.sm) {
                Text(message)
                DisclosureGroup("error.details") {
                    Text(detail)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } actions: {
            if let retry {
                Button("action.retry", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// First paint: rows shaped like the real list, redacted, instead of a centred spinner.
struct SkeletonList: View {
    var rows = 6

    var body: some View {
        List(0..<rows, id: \.self) { _ in
            Text("loading.placeholderRow")
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel(Text("loading.accessibility"))
    }
}

/// A one-line text prompt (create, rename), as an alert with a text field.
struct TextPrompt: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    var text: String
    let confirm: LocalizedStringKey
    let action: (String) -> Void
}

extension View {
    func textPrompt(_ prompt: Binding<TextPrompt?>) -> some View {
        alert(prompt.wrappedValue?.title ?? "", isPresented: Binding(
            get: { prompt.wrappedValue != nil },
            set: { if !$0 { prompt.wrappedValue = nil } }
        ), presenting: prompt.wrappedValue) { p in
            TextField("field.name", text: Binding(
                get: { prompt.wrappedValue?.text ?? p.text },
                set: { prompt.wrappedValue?.text = $0 }
            ))
            Button(p.confirm) { p.action(prompt.wrappedValue?.text ?? p.text) }
            Button("action.cancel", role: .cancel) {}
        }
    }

    /// Shows a validation or storage error as an alert.
    func errorAlert(_ error: Binding<LocalizedStringKey?>) -> some View {
        alert("error.title", isPresented: Binding(
            get: { error.wrappedValue != nil },
            set: { if !$0 { error.wrappedValue = nil } }
        )) {
            Button("action.ok", role: .cancel) {}
        } message: {
            Text(error.wrappedValue ?? "")
        }
    }
}

/// Runs a reference-data change and turns a failure into a translated message.
@MainActor
func attempt(_ message: Binding<LocalizedStringKey?>, _ body: () throws -> Void) {
    do {
        try body()
    } catch let e as ValidationError {
        message.wrappedValue = e.message
    } catch {
        AppModel.log.error("change failed: \(String(describing: error), privacy: .private)")
        message.wrappedValue = "error.generic"
    }
}
