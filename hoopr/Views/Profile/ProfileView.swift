import SwiftUI

/// Full-screen profile. Presented in place of the main tab interface rather
/// than inside it, so it owns the whole screen including its own back button.
struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    private let onBack: () -> Void

    /// Presented separately from `viewModel.editingField`, which is strictly
    /// the profile *document*'s editable fields — appearance is stored on the
    /// device and saves without a network round trip, so it shares none of
    /// that sheet's in-flight and failure handling.
    @State private var isEditingAppearance = false

    @AppStorage(AppearancePreference.storageKey)
    private var appearance: AppearancePreference = .system

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
                // Floored so the identity block never gets crushed on short
                // devices, where 3/12 of the screen is under 180pt.
                header(height: max(geo.size.height * Self.headerHeightRatio, 180))

                ScrollView {
                    fields
                        .padding(.top, 12)
                }
            }
        }
        .background(Color.hooprBackground)
        // Pinned as a safe-area inset rather than the last item in the stack,
        // so a growing field list can never push it off the bottom edge.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .sheet(item: $viewModel.editingField) { field in
            editSheet(for: field)
        }
        .sheet(isPresented: $isEditingAppearance) {
            AppearanceSheet(preference: $appearance) {
                isEditingAppearance = false
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            // Errors raised outside a sheet (profile load, sign-out) still
            // need somewhere to surface.
            if viewModel.editingField == nil, let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            signOutButton
        }
        .padding(.top, 12)
        .background(Color.hooprBackground)
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
                        .hooprFont(19, weight: .semibold)
                        .foregroundStyle(Color.hooprOnBrand)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Back to home")
                Spacer()
            }
            .padding(.horizontal, 8)

            // Capped, unlike the spacer below — the two used to split the
            // remaining space evenly, which centered the identity block
            // rather than pulling it up toward the back button.
            Spacer(minLength: 0)
                .frame(maxHeight: 8)

            avatar(size: Self.avatarSize(forHeaderHeight: height))

            Text(viewModel.userName ?? " ")
                .hooprFont(34, weight: .bold)
                .foregroundStyle(Color.hooprOnBrand)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.top, 20)
                .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        // `.frame(height:)` fixes the layout slot but doesn't clip — without
        // this, content that needs more room than the slot (e.g. the name at
        // a large scale factor on a short device) paints past the boundary
        // instead of being contained inside it.
        .clipped()
        // Bleeds the orange under the status bar while the content above
        // still lays out within the safe area.
        .background(Color.hooprOrange.ignoresSafeArea(edges: .top))
    }

    /// Scales with the header so the avatar and name still fit on short
    /// devices, where 3/12 of the screen is well under 200pt.
    private static func avatarSize(forHeaderHeight height: CGFloat) -> CGFloat {
        min(104, max(64, height * 0.46))
    }

    private func avatar(size: CGFloat) -> some View {
        ZStack {
            Circle()
                // Sits on the brand orange, which doesn't invert, so this is
                // the on-brand white in both appearances rather than a surface.
                .fill(Color.hooprOnBrand)
                .frame(width: size, height: size)
            Image(systemName: "person.fill")
                // Deliberately *not* Dynamic Type: the glyph is sized as a
                // fraction of a circle whose diameter is fixed by the header
                // height, so scaling it would push it past its own container.
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

            ProfileFieldRow(
                label: "Preferred Radius",
                value: viewModel.preferredRadiusText,
                placeholder: viewModel.defaultRadiusText,
                onEdit: { viewModel.beginEditing(.preferredRadius) }
            )

            divider

            // Device-local, not part of the profile document — see
            // `AppearancePreference`. It sits among the stored fields because
            // this is where a user looks for a setting, not because it shares
            // their storage.
            ProfileFieldRow(
                label: "Appearance",
                value: appearance.title,
                placeholder: AppearancePreference.system.title,
                onEdit: { isEditingAppearance = true }
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
            .fill(Color.hooprBorder)
            .frame(height: 1)
            .padding(.horizontal, 20)
    }

    // MARK: - Sign out

    private var signOutButton: some View {
        Button {
            viewModel.signOut()
        } label: {
            Text("Sign Out")
                .hooprFont(17, weight: .semibold, maximumSize: 24)
                .foregroundStyle(Color.hooprRed)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.hooprFill)
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
                // A failed save outranks the inline hint: the hint describes
                // the draft, the error describes what just happened to it.
                errorMessage: viewModel.errorMessage ?? viewModel.nameDraftHint,
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

        case .preferredRadius:
            EditRadiusSheet(
                radius: $viewModel.radiusDraft,
                isSaving: viewModel.isSaving,
                errorMessage: viewModel.errorMessage,
                onSave: { Task { await viewModel.saveRadius() } },
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
