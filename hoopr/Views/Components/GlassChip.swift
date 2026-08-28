import SwiftUI

/// A filter chip floating over the map.
///
/// Extracted from `MapTab` so the one non-obvious decision here lives in one
/// place: **selection tints the glass rather than swapping to an opaque fill.**
/// An active chip should read as the same object lit up, not as a different
/// control that replaced it — swapping the material makes the row look like it
/// re-rendered rather than responded.
struct GlassChip: View {
    let symbolName: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbolName)
                    .hooprFont(11, weight: .semibold)
                Text(label)
                    .hooprFont(13, weight: .semibold)
                    .lineLimit(1)
            }
            // Black on the brand orange, never white: `hooprOnBrand` is the
            // only foreground that clears AA against it.
            .foregroundStyle(isActive ? Color.hooprOnBrand : Color.hooprPrimaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(
                isActive
                    ? .regular.tint(Color.hooprOrange).interactive()
                    : .regular.interactive(),
                in: .capsule
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}
