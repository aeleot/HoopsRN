import SwiftUI

/// The app's name as a mark: the basketball — the app icon's own glyph, in the
/// brand accent — beside "hoopsRN".
///
/// Home's band opens on it (2026-09-23, the user's call: the home page needed
/// "some sort of icon, maybe the hoopsRN logo"). It is the one place in the
/// app the product names itself outside Login, and it sits where a tab's top
/// row sits, opposite the inbox button, so it costs Home no height.
///
/// Read once by VoiceOver as the app's name, not as "basketball, hoopsRN".
struct HooprWordmark: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "basketball.fill")
                .hooprType(.headline)
                .foregroundStyle(Color.hooprBrandAccent)

            Text("hoopsRN")
                .hooprType(.headline)
                .fontWeight(.bold)
                .foregroundStyle(Color.hooprPrimaryText)
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("hoopsRN")
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    HooprWordmark()
        .padding()
        .background(Color.hooprHeroBand)
}
