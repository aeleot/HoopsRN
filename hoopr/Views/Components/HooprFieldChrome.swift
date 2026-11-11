import SwiftUI

/// A text field's ground and edge in a form — Login's two fields and every
/// field on the profile's edit sheets (UI revamp Phase 6: they were two
/// identical copies).
///
/// `hooprFill` with a `hooprSeparatorStrong` edge — 3:1, because the fill
/// alone is 1.09:1 on the white page and the field would barely be drawn — and
/// a 2pt accent ring while focused.
///
/// **Its corners are the form's.** A form's submit button matches them
/// (`HooprButtonStyle.Shape.form`), so the fields and the button read as one
/// object; both read `cornerRadius` from here.
enum HooprField {
    static let cornerRadius: CGFloat = 12
    /// A floor, not a fixed height: the field grows with its text size rather
    /// than clipping it.
    static let minimumHeight: CGFloat = 52
}

extension Text {
    /// A field's placeholder, set in `hooprSecondaryText`.
    ///
    /// SwiftUI draws a placeholder in the system's own placeholder colour, and
    /// the live pass (2026-09-25) measured it at 2.6–2.9:1 in dark and 1.5:1 in
    /// light on the Map's and Friends' search fields — under AA in both. On
    /// Login it is worse than cosmetic: the placeholder is the only label
    /// either field has. Every text field passes this as its `prompt:`, so the
    /// hint reads at the same ratio as the field's own glyphs
    /// (`ThemeContrastTests`, "secondary text on fill").
    static func hooprPrompt(_ text: String) -> Text {
        Text(text).foregroundStyle(Color.hooprSecondaryText)
    }
}

extension View {
    func hooprFieldChrome(isFocused: Bool) -> some View {
        self
            .padding(.horizontal, 16)
            .frame(minHeight: HooprField.minimumHeight)
            .background(Color.hooprFill)
            .clipShape(RoundedRectangle(cornerRadius: HooprField.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: HooprField.cornerRadius)
                    .stroke(
                        isFocused ? Color.hooprBrandAccent : Color.hooprSeparatorStrong,
                        lineWidth: isFocused ? 2 : 1
                    )
            )
    }
}
