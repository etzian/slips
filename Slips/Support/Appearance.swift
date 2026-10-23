import SwiftUI

/// Theme choice of Settings › Appearance. No density setting on iPhone.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"
    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: "appearance.system"
        case .light: "appearance.light"
        case .dark: "appearance.dark"
        }
    }
}

/// Sizes the behaviour contract fixes, not visual tokens.
enum Metrics {
    /// Apple's minimum touch target.
    static let minTouchTarget: CGFloat = 44
}

extension Metrics {
    /// Width of a slip thumbnail in lists and on the review screen.
    static let thumbnailWidth: CGFloat = 72
}
