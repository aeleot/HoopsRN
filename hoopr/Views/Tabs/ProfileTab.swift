import SwiftUI

struct ProfileTab: View {
    @StateObject private var viewModel: ProfileViewModel

    init(authService: AuthService) {
        _viewModel = StateObject(wrappedValue: ProfileViewModel(authService: authService))
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Profile")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.black)

            if let email = viewModel.email {
                Text(email)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.hooprSecondaryText)
            }

            Spacer()

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.hooprRed)
            }

            Button {
                viewModel.signOut()
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
    ProfileTab(authService: AuthService())
}
