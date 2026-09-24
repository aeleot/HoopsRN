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
