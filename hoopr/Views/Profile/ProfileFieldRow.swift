import SwiftUI

/// One profile attribute: a small grey label above a larger value, centered,
/// with an optional edit affordance pinned to the trailing edge.
///
/// Passing `onEdit: nil` renders a read-only field — used for values this app
/// doesn't own (`email`, managed by Firebase Auth) or that are immutable by
/// design (`Date Joined`).
struct ProfileFieldRow: View {
    let label: String
    let value: String?
    /// Shown in place of a missing value, in secondary colour.
    let placeholder: String
    var onEdit: (() -> Void)?

    var body: some View {
        ZStack {
            VStack(spacing: 4) {
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(Color.hooprSecondaryText)

                Text(value ?? placeholder)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(value == nil ? Color.hooprSecondaryText : .black)
                    .multilineTextAlignment(.center)
            }
            // Keep the centred text clear of the trailing edit button.
            .padding(.horizontal, 52)
            .frame(maxWidth: .infinity)

            if let onEdit {
                HStack {
                    Spacer()
                    Button(action: onEdit) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.hooprOrange)
                            // 44pt keeps the tap target accessible even though
                            // the glyph is small.
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Edit \(label)")
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
    }
}

#Preview {
    VStack(spacing: 0) {
        ProfileFieldRow(label: "Username", value: "aeleot11", placeholder: "Not set", onEdit: {})
        Divider()
        ProfileFieldRow(label: "Email", value: "aeleot11@gmail.com", placeholder: "Not set")
        Divider()
        ProfileFieldRow(label: "Home Court", value: nil, placeholder: "Not set", onEdit: {})
    }
}
