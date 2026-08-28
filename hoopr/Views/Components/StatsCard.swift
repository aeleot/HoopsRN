import SwiftUI

/// Three-column summary of participation stats — Home's one historical
/// card. Text-only, built on `cardChrome()` so it reads as the same surface
/// as every other card on the screen.
struct StatsCard: View {
    let completedCount: Int
    let participationStreak: Int
    let lastCompletedText: String

    var body: some View {
        HStack(spacing: 16) {
            stat(symbol: "basketball.fill", label: "Runs", value: "\(completedCount)")
            Divider().overlay(Color.hooprBorder)
            stat(symbol: "flame.fill", label: "Streak", value: "\(participationStreak) wks")
            Divider().overlay(Color.hooprBorder)
            stat(symbol: "clock.fill", label: "Last Run", value: lastCompletedText)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardChrome()
    }

    private func stat(symbol: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .hooprFont(11)
                    .foregroundStyle(Color.hooprOrange)
                    .accessibilityHidden(true)
                Text(label)
                    .hooprFont(11, weight: .bold)
                    .foregroundStyle(Color.hooprSecondaryText)
            }
            Text(value)
                .hooprFont(15, weight: .semibold)
                .foregroundStyle(Color.hooprPrimaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
