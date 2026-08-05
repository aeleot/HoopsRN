import SwiftUI

struct ProfileTab: View {
    @EnvironmentObject var authManager: AuthManager

    private var userName: String {
        authManager.userDisplayName ?? "Player"
    }

    // Dummy values — these have no source yet; they arrive with the Firestore
    // user profile (HooprUser), unlike the name which comes from Firebase Auth.
    private let userRating = 1000
    private let playerBuild = "Slasher"
    private let gamesPlayed = 42

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [Color.hooprOrange.opacity(0.06), Color.hooprLightGray],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.45)
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    profileCard(
                        cardWidth: geo.size.width - 40,
                        cardHeight: geo.size.height * 0.4
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    gameLogSection

                    Spacer()

                    Button {
                        authManager.signOut()
                    } label: {
                        Text("Sign Out")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.hooprSecondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(Color.hooprLightGray)
    }

    @ViewBuilder
    private func profileCard(cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        let avatarSize = cardWidth / 3 - 32

        HStack(spacing: 0) {
            // Profile picture — circular, centered in left 1/3
            ZStack {
                Circle()
                    .fill(Color(red: 0.84, green: 0.85, blue: 0.88))
                Image(systemName: "person.fill")
                    .font(.system(size: avatarSize * 0.45))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(width: avatarSize, height: avatarSize)
            .frame(width: cardWidth / 3)

            // User info — right 2/3, centered
            VStack(alignment: .center, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(userName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.black)
                    Text("\(userRating)")
                        .font(.system(size: 13).italic())
                        .foregroundStyle(Color.hooprSecondaryText)
                }
                .padding(.bottom, 10)

                Text("\"\(playerBuild)\"")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.hooprSecondaryText)
                    .padding(.bottom, 20)

                VStack(alignment: .center, spacing: 2) {
                    Text("\(gamesPlayed)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.black)
                    Text("Games Played")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.hooprSecondaryText)
                }
            }
            .frame(width: cardWidth * 2 / 3, alignment: .center)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.10), radius: 14, x: 0, y: 5)
    }

    private var gameLogSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Game Log")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 16)

            Rectangle()
                .fill(Color.hooprBorderGray)
                .frame(height: 1)
                .padding(.horizontal, 20)
        }
    }
}

#Preview {
    ProfileTab()
        .environmentObject(AuthManager())
}
