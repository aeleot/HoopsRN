import SwiftUI
import UIKit

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

    /// Presented outside `viewModel.editingField` for the same reason as the
    /// appearance sheet: a password reset is a Firebase Auth action, not a
    /// write to the profile document, so it shares none of that sheet's
    /// in-flight or failure handling.
    @State private var isChangingPassword = false

    /// Drives the uid's copy glyph, which reverts to itself after a beat.
    @State private var didCopyUserId = false

    @AppStorage(AppearancePreference.storageKey)
    private var appearance: AppearancePreference = .system

    /// Proportion of the screen given to the orange identity header. The same
    /// fraction `MainTabView` pins its header slab to, so the two screens share
    /// a skyline and the profile doesn't open on a quarter-screen of orange.
    private static let headerHeightRatio: CGFloat = 0.14

    /// The gap between cards, and — because the mosaic interlocks — the amount
    /// a feature card is taller than the two tiles beside it combined.
    private static let gridSpacing: CGFloat = 12

    /// One grid unit: a short tile's *floor*, not its height. Scaled so the
    /// floor tracks the reader's text size along with everything else.
    @ScaledMetric(relativeTo: .body) private var tileHeight: CGFloat = 80

    /// A feature card's floor: it spans the two tiles beside it, gap included.
    private var featureHeight: CGFloat { tileHeight * 2 + Self.gridSpacing }

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
                // Floored so the identity row never gets crushed on short
                // devices, where 14% of the screen is under 96pt.
                header(height: max(geo.size.height * Self.headerHeightRatio, 96))

                ScrollView {
                    grid
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                }
            }
        }
        .background(Color.hooprBackground)
        // Pinned as a safe-area inset rather than the last item in the stack,
        // so a growing card grid can never push it off the bottom edge.
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
        .sheet(isPresented: $isChangingPassword) {
            // Only reachable when `canChangePassword`, which is exactly when
            // there's an email to send to.
            ChangePasswordSheet(
                email: viewModel.email ?? "",
                isSending: viewModel.isSendingPasswordReset,
                didSend: viewModel.didSendPasswordReset,
                errorMessage: viewModel.passwordResetError,
                onSend: { Task { await viewModel.sendPasswordReset() } },
                onCancel: {
                    isChangingPassword = false
                    viewModel.cancelChangingPassword()
                },
                onDone: { isChangingPassword = false }
            )
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            // The grid scrolls under this bar, so it needs an edge of its own —
            // without the rule a card is simply cut off mid-height.
            Rectangle()
                .fill(Color.hooprBorder)
                .frame(height: 1)

            VStack(spacing: 8) {
                // Errors raised outside a sheet (profile load, sign-out) still
                // need somewhere to surface.
                if viewModel.editingField == nil, let errorMessage = viewModel.errorMessage {
                    ErrorBanner(message: errorMessage)
                        .padding(.horizontal, 28)
                }

                signOutButton
            }
            .padding(.top, 16)
        }
        .background(Color.hooprBackground)
    }

    // MARK: - Header

    private func header(height: CGFloat) -> some View {
        // One row, laid out the way the identity reads: back out, then who you
        // are. At this height there's no room to stack the back button above
        // the avatar, and no need to — nothing collides in a single line.
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .hooprFont(19, weight: .semibold, maximumSize: 24)
                    .foregroundStyle(Color.hooprOnBrand)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back to home")

            avatar(size: Self.avatarSize(forHeaderHeight: height))

            VStack(alignment: .leading, spacing: 2) {
                Text(handle)
                    // Capped like the rest of the pinned header: the bar's
                    // height is a fraction of the screen, so its type can't
                    // grow freely.
                    .hooprFont(22, weight: .bold, maximumSize: 28)
                    .foregroundStyle(Color.hooprOnBrand)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                // The Auth uid. Held well below the handle in size and
                // contrast because it's a reference to quote, not something to
                // read.
                if let userId = viewModel.userId {
                    copyableUserId(userId)
                } else {
                    // Holds the line's height while the session resolves, so
                    // the handle above doesn't shift when the uid lands.
                    Text(" ")
                        .hooprFont(11, maximumSize: 14)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        // `.frame(height:)` fixes the layout slot but doesn't clip — without
        // this, content that needs more room than the slot (e.g. the name at
        // a large scale factor on a short device) paints past the boundary
        // instead of being contained inside it.
        .clipped()
        // Bleeds the orange under the status bar while the content above
        // still lays out within the safe area. The gradient runs into
        // `hooprDarkOrange` at the bottom so the header settles into the card
        // grid instead of ending on a flat band.
        .background(
            LinearGradient(
                colors: [Color.hooprOrange, Color.hooprDarkOrange],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    /// The uid, with a tap that puts it on the pasteboard — quoting it in a
    /// bug report is the only reason it's on screen, and a 28-character string
    /// is not something anyone should retype.
    ///
    /// The glyph swaps to a checkmark on success rather than raising a toast:
    /// the confirmation belongs where the tap was, and this header has no room
    /// for anything larger.
    private func copyableUserId(_ userId: String) -> some View {
        Button {
            UIPasteboard.general.string = userId
            withAnimation(.easeInOut(duration: 0.15)) {
                didCopyUserId = true
            }
            // Reverts on its own; a copy affordance that stays "copied" stops
            // reading as a button.
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.easeInOut(duration: 0.15)) {
                    didCopyUserId = false
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(userId)
                    .hooprFont(11, maximumSize: 14)
                    .italic()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Image(systemName: didCopyUserId ? "checkmark" : "doc.on.doc")
                    .hooprFont(10, weight: .semibold, maximumSize: 13)
            }
            .foregroundStyle(Color.hooprOnBrand.opacity(0.75))
            // The row is short, so the whole of it — uid included — is the
            // target rather than just the glyph.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy user ID")
        .accessibilityValue(userId)
    }

    /// The identity line. `userName` is a *display* name, not a stored handle
    /// (see `UserProfile`), so the `@` form is a rendering of it — whitespace
    /// removed, because "@Elliot Aeleot" doesn't read as one thing.
    ///
    /// A single space while the first snapshot is in flight, so the row holds
    /// its height instead of jumping when the name lands.
    private var handle: String {
        guard let userName = viewModel.userName else { return " " }
        return "@" + userName.filter { !$0.isWhitespace }
    }

    /// Scales with the header, which is now a fraction of the screen rather
    /// than a quarter of it — the avatar has to fit inside a bar, not fill a
    /// slab.
    private static func avatarSize(forHeaderHeight height: CGFloat) -> CGFloat {
        min(56, max(38, height * 0.44))
    }

    private func avatar(size: CGFloat) -> some View {
        ZStack {
            Circle()
                // Sits on the brand orange, which doesn't invert, so this is
                // the on-brand white in both appearances rather than a surface.
                .fill(Color.hooprOnBrand)
                .frame(width: size, height: size)

            Group {
                if let initials = Self.initials(for: viewModel.userName) {
                    Text(initials)
                        // Deliberately *not* Dynamic Type, as with the glyph
                        // below: both are sized as a fraction of a circle whose
                        // diameter is fixed by the header height, so scaling
                        // them would push them past their own container.
                        .font(.system(size: size * 0.38, weight: .bold))
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.5))
                }
            }
            .foregroundStyle(Color.hooprOrange)
        }
        // A hairline ring, so the white circle still separates from the header
        // rather than dissolving into it at the top of the gradient.
        .overlay(
            Circle()
                .stroke(Color.hooprOnBrand.opacity(0.35), lineWidth: 2)
                .frame(width: size + 6, height: size + 6)
        )
        .accessibilityHidden(true)
    }

    /// Up to two initials from the display name, or `nil` while the first
    /// snapshot is in flight — or for a name that's all punctuation, where the
    /// person glyph says more than an empty circle would.
    private static func initials(for name: String?) -> String? {
        guard let name else { return nil }

        let letters = name
            .split(whereSeparator: \.isWhitespace)
            .compactMap { $0.first(where: \.isLetter) }
            .prefix(2)

        return letters.isEmpty ? nil : String(letters).uppercased()
    }

    // MARK: - Card grid

    /// The profile as a mosaic rather than a list: each attribute gets a card
    /// sized to what it holds, and the cards interlock — a tall one beside a
    /// stacked pair, a full-width one under both — so the page reads as a whole
    /// instead of as six rows separated by rules.
    ///
    /// **Cards state a floor, never a fixed height.** A fixed height doesn't
    /// clip — a card whose content needs more room paints outside its own
    /// frame and over its neighbour — so every card takes
    /// `minHeight: … , maxHeight: .infinity` instead: it can't be shorter than
    /// its grid unit, it grows if its content needs to, and being stretchable
    /// means the tallest card in a row pulls the rest up to match it. That's
    /// what keeps the seams aligned at every Dynamic Type size, without this
    /// view having to predict how tall any card's text will be.
    private var grid: some View {
        VStack(alignment: .leading, spacing: 20) {
            section("Your Game") {
                HStack(alignment: .top, spacing: Self.gridSpacing) {
                    // The one card that leads the page: it's the setting the
                    // rest of the app is organised around.
                    ProfileCard(
                        symbol: "basketball.fill",
                        label: "Home Court",
                        value: viewModel.homeCourtName,
                        placeholder: "Not set",
                        detail: viewModel.homeCourtCity,
                        prominence: .feature,
                        onEdit: { viewModel.beginEditing(.homeCourt) }
                    )
                    .frame(minHeight: featureHeight, maxHeight: .infinity)

                    VStack(spacing: Self.gridSpacing) {
                        // Read-only here by design: courts are starred from the
                        // map, so this counts them rather than editing them.
                        ProfileCard(
                            symbol: "star.fill",
                            label: "Favorites",
                            value: viewModel.favoriteCourtCountText,
                            placeholder: "0",
                            detail: viewModel.favoriteCourtUnitText
                        )
                        .frame(minHeight: tileHeight, maxHeight: .infinity)

                        ProfileCard(
                            symbol: "location.circle.fill",
                            label: "Radius",
                            value: viewModel.preferredRadiusText,
                            placeholder: viewModel.defaultRadiusText,
                            detail: "around you",
                            onEdit: { viewModel.beginEditing(.preferredRadius) }
                        )
                        .frame(minHeight: tileHeight, maxHeight: .infinity)
                    }
                }
            }

            section("Account") {
                HStack(alignment: .top, spacing: Self.gridSpacing) {
                    ProfileCard(
                        symbol: "person.fill",
                        label: "Username",
                        value: viewModel.userName,
                        placeholder: "Not set",
                        onEdit: { viewModel.beginEditing(.userName) }
                    )
                    .frame(minHeight: tileHeight, maxHeight: .infinity)

                    // The value is a stand-in, not the password: Firebase Auth
                    // stores a hash and this app never sees one, so there is
                    // nothing real to render. Editing it sends a reset link
                    // rather than opening a field — and goes read-only when
                    // there's no address to send to.
                    ProfileCard(
                        symbol: "lock.fill",
                        label: "Password",
                        value: "••••••••",
                        placeholder: "••••••••",
                        onEdit: viewModel.canChangePassword ? {
                            viewModel.beginChangingPassword()
                            isChangingPassword = true
                        } : nil
                    )
                    .frame(minHeight: tileHeight, maxHeight: .infinity)
                }

                // Full width because it's the longest value on the page — an
                // address at half width would shrink to fit rather than read.
                // Read-only: email belongs to Firebase Auth, and changing it
                // needs a re-authentication flow this screen doesn't have yet.
                ProfileCard(
                    symbol: "envelope.fill",
                    label: "Email",
                    value: viewModel.email,
                    placeholder: "Not set"
                )
                .frame(minHeight: tileHeight)

                HStack(alignment: .top, spacing: Self.gridSpacing) {
                    // Device-local, not part of the profile document — see
                    // `AppearancePreference`. It sits among the stored fields
                    // because this is where a user looks for a setting, not
                    // because it shares their storage.
                    ProfileCard(
                        symbol: appearance.symbolName,
                        label: "Appearance",
                        value: appearance.title,
                        placeholder: AppearancePreference.system.title,
                        onEdit: { isEditingAppearance = true }
                    )
                    .frame(minHeight: tileHeight, maxHeight: .infinity)

                    // Immutable by design — `createdAt` is write-once
                    // server-side.
                    ProfileCard(
                        symbol: "calendar",
                        label: "Joined",
                        value: viewModel.dateJoinedText,
                        placeholder: "—"
                    )
                    .frame(minHeight: tileHeight, maxHeight: .infinity)
                }
            }
        }
    }

    /// A titled group of cards, using the same section heading as the Local
    /// Runs tab so the two screens read as one app.
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Self.gridSpacing) {
            Text(title)
                .hooprFont(18, weight: .bold)
                .foregroundStyle(Color.hooprPrimaryText)

            content()
        }
    }

    // MARK: - Sign out

    private var signOutButton: some View {
        Button {
            viewModel.signOut()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .hooprFont(15, weight: .semibold, maximumSize: 20)
                Text("Sign Out")
                    .hooprFont(17, weight: .semibold, maximumSize: 24)
            }
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
