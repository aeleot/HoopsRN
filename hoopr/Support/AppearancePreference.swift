import SwiftUI
import UIKit

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

    /// What the window is pinned to (`windowAppearance(_:)`). `.unspecified`
    /// gives the choice back to the system, which is what makes `.system` a
    /// genuine pass-through rather than a third palette.
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light:  .light
        case .dark:   .dark
        }
    }
}

extension View {
    /// Pins the window this view is in to `preference`, and everything in that
    /// window with it — see `WindowAppearance`. Applied once, at the root.
    func windowAppearance(_ preference: AppearancePreference) -> some View {
        background(
            WindowAppearance(style: preference.userInterfaceStyle)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
    }
}

/// Applies the appearance preference to the window itself, rather than through
/// `preferredColorScheme`.
///
/// **Why not `preferredColorScheme`** (2026-10-06). SwiftUI pins a sheet to
/// the scheme in force when it is presented and doesn't update it, so the
/// Appearance sheet — the one place the preference changes — stayed in the old
/// palette while the app behind it recoloured, and the rows that redrew came
/// out in the new one: a dark sheet with light mode's deep-orange check on it.
/// The window's `overrideUserInterfaceStyle` is inherited by everything in it —
/// every screen, a sheet that is already up, the UIKit map — so they all change
/// together, and `.unspecified` hands System back cleanly.
///
/// A zero-size view: it pins its window when it joins one, and again on every
/// change, cross-fading the whole window (`Motion.Duration.appearance`).
private struct WindowAppearance: UIViewRepresentable {
    let style: UIUserInterfaceStyle

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        probe.style = style
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        probe.style = style
    }

    final class Probe: UIView {
        var style: UIUserInterfaceStyle = .unspecified {
            didSet {
                if style != oldValue { apply(animated: true) }
            }
        }

        /// Unanimated: on launch the window should open in its palette, not
        /// fade into it.
        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply(animated: false)
        }

        private func apply(animated: Bool) {
            guard let window, window.overrideUserInterfaceStyle != style else { return }
            let style = self.style
            guard animated else {
                window.overrideUserInterfaceStyle = style
                return
            }
            UIView.transition(
                with: window,
                duration: Motion.Duration.appearance,
                options: [.transitionCrossDissolve, .allowUserInteraction]
            ) {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}
