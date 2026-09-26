import SwiftUI

/// Compact drawing, full-size target. Its solid ground belongs to the band.
struct FilterChip: View {
    let symbolName: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    static let drawnHeight: CGFloat = 28
    static let tapTarget: CGFloat = 44

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: symbolName)
                Text(label)
            }
            .hooprType(.caption)
            .fontWeight(.semibold)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(isActive ? Color.hooprOnBrand : Color.hooprPrimaryText)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .frame(minHeight: Self.drawnHeight)
            .background(isActive ? Color.hooprOrange : Color.hooprHeroBand, in: Capsule())
            .overlay {
                if !isActive {
                    Capsule().strokeBorder(Color.hooprSeparatorStrong, lineWidth: 1)
                }
            }
            .frame(minWidth: Self.tapTarget, minHeight: Self.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
