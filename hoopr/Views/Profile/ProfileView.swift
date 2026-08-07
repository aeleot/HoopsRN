import SwiftUI

/// Full-screen profile. Presented in place of the main tab interface rather
/// than inside it, so it owns the whole screen including its own back button.
struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    private let onBack: () -> Void

    /// Proportion of the screen given to the orange identity header.
    private static let headerHeightRatio: CGFloat = 3.0 / 12.0

    init(
        authService: AuthService,
        userProfileService: UserProfileService,
        courtService: CourtService,
        onBack: @escaping () -> Void
    ) {
        self.onBack = onBack
        _viewModel = StateObject(wrappedValue: ProfileViewModel(
            authService: authService,
            userProfileService: userProfileService,
            courtService: courtService
        ))
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                header(height: geo.size.height * Self.headerHeightRatio)

                ScrollView {
                    fields
                        .padding(.top, 8)
                }

                // Errors raised outside a sheet (profile load, sign-out) still
                // need somewhere to surface.
                if viewModel.editingField == nil, let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.hooprRed)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 8)
                }

                signOutButton
            }
        }
        .background(Color.white)
        .sheet(item: $viewModel.editingField) { field in
            editSheet(for: field)
        }
    }

    // MARK: - Header

    private func header(height: CGFloat) -> some View {
        // The back button flows above the identity block rather than being
        // overlaid on it — at this header height an overlay would collide
        // with the avatar on shorter devices.
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Back to home")
                Spacer()
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 0)

            avatar(size: Self.avatarSize(forHeaderHeight: height))

            Text(viewModel.userName ?? " ")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.top, 10)
                .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        // Bleeds the orange under the status bar while the content above
        // still lays out within the safe area.
        .background(Color.hooprOrange.ignoresSafeArea(edges: .top))
    }

    /// Scales with the header so the avatar and name still fit on short
    /// devices, where 3/12 of the screen is well under 200pt.
    private static func avatarSize(forHeaderHeight height: CGFloat) -> CGFloat {
        min(88, max(56, height * 0.40))
    }

    private func avatar(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: size, height: size)
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.5))
                .foregroundStyle(Color.hooprOrange)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Fields

    private var fields: some View {
        VStack(spacing: 0) {
            ProfileFieldRow(
                label: "Username",
                value: viewModel.userName,
                placeholder: "Not set",
                onEdit: { viewModel.beginEditing(.userName) }
            )

            divider

            // Read-only: email belongs to Firebase Auth, and changing it needs
            // a re-authentication flow this screen doesn't have yet.
            ProfileFieldRow(
                label: "Email",
                value: viewModel.email,
                placeholder: "Not set"
            )

            divider

            ProfileFieldRow(
                label: "Home Court",
                value: viewModel.homeCourtName,
                placeholder: "Not set",
                onEdit: { viewModel.beginEditing(.homeCourt) }
            )

            divider

            // Immutable by design — `createdAt` is write-once server-side.
            ProfileFieldRow(
                label: "Date Joined",
                value: viewModel.dateJoinedText,
                placeholder: "—"
            )
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.hooprBorderGray)
            .frame(height: 1)
            .padding(.horizontal, 20)
    }

    // MARK: - Sign out

    private var signOutButton: some View {
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

    // MARK: - Edit sheets

    @ViewBuilder
    private func editSheet(for field: ProfileViewModel.EditableField) -> some View {
        switch field {
        case .userName:
            EditUserNameSheet(
                draft: $viewModel.nameDraft,
                isSaving: viewModel.isSaving,
                canSave: viewModel.canSaveName,
                errorMessage: viewModel.errorMessage,
                onSave: { Task { await viewModel.saveName() } },
                onCancel: { viewModel.cancelEditing() }
            )

        case .homeCourt:
            HomeCourtPickerSheet(
                courts: viewModel.courts,
                selectedCourtId: viewModel.homeCourtId,
                isSaving: viewModel.isSaving,
                errorMessage: viewModel.errorMessage,
                onSelect: { courtId in Task { await viewModel.saveHomeCourt(courtId) } },
                onCancel: { viewModel.cancelEditing() }
            )
        }
    }
}

#Preview {
    let authService = AuthService()
    ProfileView(
        authService: authService,
        userProfileService: UserProfileService(authService: authService),
        courtService: CourtService(),
        onBack: {}
    )
}
