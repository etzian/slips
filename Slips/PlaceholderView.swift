import SwiftUI

struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: EZ.Space.md) {
            Text("placeholder.title")
                .font(.title)
                .foregroundStyle(EZ.Color.text)
        }
        .padding(EZ.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EZ.Color.bg)
        .accessibilityIdentifier("placeholder")
    }
}
