import SwiftUI

/// The back button for a pushed screen that opens on a hero band, drawn inside
/// the band instead of in a navigation bar above it.
///
/// **Why the screen hides its bar.** With the system bar showing, the band
/// started below it, and the bar's own strip of page background sat between
/// the status bar and the band. On squad detail that read as the header being
/// cut off at the top (the user's words, 2026-09-23), and it didn't match the
/// tab the screen was pushed from, whose band starts at the safe area. So the
/// pushed screen hides the bar and puts this in the band's first row, in
/// `ProfileButton.Slot`'s frame and at its height, mirrored to the leading
/// edge. The band then starts where the tab's does.
///
/// Glass in a circle, like the iOS 26 system back button it replaces, so it
/// still reads as "back" at a glance. `dismiss()` pops the navigation stack.
/// The screen keeps its `navigationTitle` for VoiceOver.
struct BandBackButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .hooprFont(17, weight: .semibold, maximumSize: 22)
                .foregroundStyle(Color.hooprPrimaryText)
                .frame(width: ProfileButton.Slot.size, height: ProfileButton.Slot.size)
                .hooprGlass(in: .circle)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}
