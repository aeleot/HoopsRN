import SwiftUI

struct ProfileTab: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Profile")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.black)

            if let email = authManager.userEmail {
                Text(email)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.hooprSecondaryText)
            }

            Spacer()

            Button {
                authManager.signOut()
            } label: {
                Text("Sign Out")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.hooprRed)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.hooprLightGray)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

#Preview {
    ProfileTab()
        .environmentObject(AuthManager())
}
