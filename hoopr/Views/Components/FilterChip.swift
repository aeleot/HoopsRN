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
            .background(isActive ? Color.hooprOrange : Color.hooprElevatedSurface, in: Capsule())
            .shadow(color: .black.opacity(isActive ? 0.18 : 0.14), radius: 4, x: 0, y: 2)
            .shadow(color: .black.opacity(0.06), radius: 1, x: 0, y: 0.5)
            .frame(minWidth: Self.tapTarget, minHeight: Self.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
