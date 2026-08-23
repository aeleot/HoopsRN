import SwiftUI

/// Whether the app follows the device's appearance or is pinned to one of the
/// two palettes in `Theme.swift`.
///
/// Stored in `UserDefaults` rather than the profile document, and deliberately:
/// this is a property of the *device*, not the account. Someone signed in on a
/// phone and an iPad can reasonably want dark on one and light on the other,
/// and routing it through Firestore would also mean a schema change, a rules
/// change, and an appearance that flickers on launch while the first snapshot
/// is still in flight.
enum AppearancePreference: String, CaseIterable, Identifiable {
    /// Follow the device. The default, and what the app did before this
    /// setting existed.
    case system
    case light
    case dark

    /// Read by `hooprApp` (which applies it) and by `ProfileView` (which edits
    /// it). Both use `@AppStorage`, so the write on one side reaches the other
    /// without anything being passed between them.
    static let storageKey = "appearance.preference"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light:  "Light"
        case .dark:   "Dark"
        }
    }

    var subtitle: String {
        switch self {
        case .system: "Match your device settings"
        case .light:  "Always light"
        case .dark:   "Always dark"
        }
    }

    var symbolName: String {
        switch self {
        case .system: "iphone"
        case .light:  "sun.max.fill"
        case .dark:   "moon.fill"
        }
    }

    /// What to hand `preferredColorScheme`. `nil` gives the choice back to the
    /// system, which is what makes `.system` a genuine pass-through rather than
    /// a third palette.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }
}
