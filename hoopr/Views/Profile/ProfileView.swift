import SwiftUI

/// Full-screen profile. Presented in place of the main tab interface rather
/// than inside it, so it owns the whole screen including its own back button.
///
/// **Two panes, one screen.** Friends used to be the third tab of
/// `MainTabView`; it lives here now, behind a selector under the identity
/// block, and the shell got a tab slot back for it. The pairing isn't
/// arbitrary — both panes answer "who am I in this app", one about your own
/// settings and one about the people attached to them — and it's what lets a
/// friend request be visible from the same place you'd go to change your home
/// court.
///
/// **One scroll view owns the whole page.** The identity block scrolls away
/// like any other content; the pane selector — plus the friends toolbar, when
/// that pane is showing — is a *pinned section header*, so it stops under the
/// top bar and stays there. That's the mechanism behind the two rules this
/// screen used to enforce with pinned containers: the search field never
/// scrolls out of reach, and the identity never costs a fixed slab of screen.
struct ProfileView: View {
    /// Which half of the screen is showing. Ordered as the selector renders
    /// them, left to right.
    enum Pane: Hashable, CaseIterable {
        case profile
        case friends

        var title: String {
            switch self {
            case .profile: "Profile"
            case .friends: "Friends"
            }
        }

        var symbol: String {
            switch self {
            case .profile: "person.crop.circle"
            case .friends: "person.2.fill"
            }
        }
    }

    @StateObject private var viewModel: ProfileViewModel

    /// Held by the screen rather than by the friends pane, so search text and
    /// results survive a trip through the Profile pane and back — the pane's
    /// views are stateless and are rebuilt on every switch.
    @StateObject private var friendsViewModel: FriendsViewModel

    private let onBack: () -> Void

    @State private var pane: Pane = .profile

    /// How far the content has scrolled, and how tall the identity block is —
    /// together they say whether the top bar has anything to show. See
    /// `barProgress`.
    @State private var scrollOffset: CGFloat = 0
    @State private var identityHeight: CGFloat = 0

    /// Slides the selection behind the pane selector's pills.
    @Namespace private var paneSelection

    // MARK: Friends-pane presentation
    //
    // Owned here rather than by `FriendsPaneContent` because the toolbar that
    // opens the inbox and the list that opens a profile are two separate views
    // in two separate parts of the scroll — there is no single pane view left
    // to hold this between them.

    @FocusState private var isSearchFocused: Bool
    @State private var isInboxPresented = false
    @State private var presentedPlayer: PlayerRoute?

    /// Which friend a remove confirmation is about. Held here rather than on
    /// the row so the dialog survives the row being re-created by a snapshot
    /// arriving mid-confirmation.
    @State private var pendingRemoval: FriendsViewModel.Row?

    // MARK: Profile-pane presentation

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

    @AppStorage(AppearancePreference.storageKey)
    private var appearance: AppearancePreference = .system

    /// The page margin, and the gap between rows.
    private static let pageMargin: CGFloat = 20
    private static let rowSpacing: CGFloat = 10

    init(
        authService: AuthService,
        userProfileService: UserProfileService,
        courtService: CourtService,
        friendService: FriendService,
        onBack: @escaping () -> Void
    ) {
        self.onBack = onBack
        _viewModel = StateObject(wrappedValue: ProfileViewModel(
            authService: authService,
            userProfileService: userProfileService,
            courtService: courtService
        ))
        _friendsViewModel = StateObject(wrappedValue: FriendsViewModel(
            friendService: friendService,
            userProfileService: userProfileService,
            courtService: courtService
        ))
    }

    var body: some View {
        page
            .sheet(item: $viewModel.editingField) { field in
                editSheet(for: field)
            }
            .sheet(isPresented: $isEditingAppearance) {
                AppearanceSheet(preference: $appearance) {
                    isEditingAppearance = false
                }
            }
            .sheet(isPresented: $isChangingPassword) {
                // Only reachable when `canChangePassword`, which is exactly
                // when there's an email to send to.
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
            .sheet(isPresented: $isInboxPresented) {
                InboxSheet(viewModel: friendsViewModel) {
                    isInboxPresented = false
                }
            }
            .sheet(item: $presentedPlayer) { route in
                PlayerProfileSheet(uid: route.uid, viewModel: friendsViewModel) {
                    presentedPlayer = nil
                }
            }
            .confirmationDialog(
                "Remove \(pendingRemoval?.nameForProse ?? "this player")?",
                isPresented: .init(
                    get: { pendingRemoval != nil },
                    set: { if !$0 { pendingRemoval = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let uid = pendingRemoval?.uid {
                        Task { await friendsViewModel.perform(.remove, on: uid) }
                    }
                    pendingRemoval = nil
                }
                Button("Keep", role: .cancel) { pendingRemoval = nil }
            } message: {
                Text("You'll both drop off each other's friends list. You can add them again later.")
            }
    }

    /// The page itself, without its presentation. Split from `body` only so the
    /// sheets and dialogs the two panes brought with them don't bury it.
    private var page: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                identity

                Section {
                    paneContent
                        .padding(.horizontal, Self.pageMargin)
                        .padding(.bottom, 40)
                } header: {
                    paneHeader
                }
            }
        }
        .background(Color.hooprBackground)
        .scrollDismissesKeyboard(.interactively)
        // Measured against the top of the *content*, inset included, so it
        // reads 0 at rest whatever the top bar's height works out to.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            scrollOffset = offset
        }
        // A safe-area inset rather than an overlay: this way the scroll view
        // knows the bar is there, and the pinned pane header stops underneath
        // it instead of sliding up under the status bar.
        .safeAreaInset(edge: .top, spacing: 0) {
            ProfileTopBar(
                handle: handle,
                initial: initials,
                progress: barProgress,
                unansweredCount: friendsViewModel.unansweredCount,
                badgeText: friendsViewModel.badgeText,
                onBack: onBack,
                onOpenInbox: {
                    isSearchFocused = false
                    isInboxPresented = true
                }
            )
        }
    }

    // MARK: - Identity

    private var identity: some View {
        ProfileIdentityBlock(
            handle: handle,
            initial: initials,
            userId: viewModel.userId
        )
        .padding(.horizontal, Self.pageMargin)
        .padding(.top, 8)
        .padding(.bottom, 22)
        // Measured rather than assumed: the block's height moves with the
        // reader's text size, and it's what decides when the top bar's title
        // has a reason to appear.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            identityHeight = height
        }
    }

    /// 0 while the identity block is still readable, 1 once it's behind the
    /// bar, crossing over the last 32pt of its travel. Guarded on a measured
    /// height so the bar can't come up titled on first layout.
    private var barProgress: Double {
        guard identityHeight > 0 else { return 0 }
        let fadeDistance: CGFloat = 32
        let start = identityHeight - fadeDistance - 20
        return Double(min(max((scrollOffset - start) / fadeDistance, 0), 1))
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

    /// Up to two initials from the display name, or empty — which selects
    /// `PlayerAvatar`'s glyph — while the first snapshot is in flight, and for
    /// a name that's all punctuation.
    private var initials: String {
        guard let name = viewModel.userName else { return "" }

        let letters = name
            .split(whereSeparator: \.isWhitespace)
            .compactMap { $0.first(where: \.isLetter) }
            .prefix(2)

        return String(letters).uppercased()
    }

    // MARK: - Pane selector

    /// Everything that pins: the pane selector, and — on the Friends pane — the
    /// search field that pane refuses to let scroll away.
    ///
    /// Opaque, because rows scroll directly underneath it.
    private var paneHeader: some View {
        VStack(spacing: 12) {
            paneSelector

            if pane == .friends {
                FriendsSearchField(
                    viewModel: friendsViewModel,
                    isSearchFocused: $isSearchFocused
                )
            }
        }
        .padding(.horizontal, Self.pageMargin)
        .padding(.top, 4)
        .padding(.bottom, 14)
        .background(Color.hooprBackground)
        .overlay(alignment: .bottom) {
            // Only once something is actually scrolling under the header —
            // a rule under a header at rest reads as a divider in the page.
            Rectangle()
                .fill(Color.hooprBorder)
                .frame(height: 1)
                .opacity(barProgress)
        }
    }

    /// A segmented control rather than the shell's glass pills: those float
    /// over a live map and need to refract it, while this sits on a flat page
    /// where a solid selection is simply easier to read.
    private var paneSelector: some View {
        HStack(spacing: 4) {
            ForEach(Pane.allCases, id: \.self) { item in
                let isSelected = pane == item

                Button {
                    isSearchFocused = false
                    withAnimation(.easeInOut(duration: 0.2)) {
                        pane = item
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.symbol)
                            .hooprFont(12, weight: .medium, maximumSize: 15)

                        Text(item.title)
                            .hooprFont(14, weight: .semibold, maximumSize: 18)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        // No badge here. This segment used to carry a dot for
                        // waiting requests, which was only honest while the
                        // inbox was inside the pane it selects. The inbox is in
                        // the top bar now and its badge is visible from both
                        // panes, so a second indicator would point at a place
                        // the requests no longer live.
                    }
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(
                        isSelected ? Color.hooprOnBrand : Color.hooprSecondaryText
                    )
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.hooprOrange)
                                // One shape moved between the two pills rather
                                // than two shapes fading, so the selection
                                // slides.
                                .matchedGeometryEffect(id: "pane", in: paneSelection)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.hooprFill)
        )
    }

    // MARK: - Panes

    @ViewBuilder
    private var paneContent: some View {
        switch pane {
        case .profile:
            profileFields

        case .friends:
            FriendsPaneContent(
                viewModel: friendsViewModel,
                onOpenPlayer: { presentedPlayer = PlayerRoute(uid: $0) },
                onRequestRemoval: { pendingRemoval = $0 }
            )
        }
    }

    /// The profile as one column of rows: every field on a line of its own,
    /// each led by its symbol, values free to run the width of the page.
    private var profileFields: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Errors raised outside a sheet — a profile load, a sign-out — used
            // to surface in a pinned bottom bar. There isn't one any more, so
            // they lead the pane instead, where they're read before the fields
            // they're about.
            if viewModel.editingField == nil, let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage)
            }

            section("Your Game") {
                // The setting the rest of the app is organised around, so it
                // leads — first row, and the only one carrying a second fact.
                ProfileRow(
                    symbol: "basketball.fill",
                    label: "Home Court",
                    value: viewModel.homeCourtName,
                    placeholder: "Not set",
                    detail: viewModel.homeCourtCity,
                    onTap: { viewModel.beginEditing(.homeCourt) }
                )

                // Read-only here by design: courts are starred from the map, so
                // this counts them rather than editing them.
                ProfileRow(
                    symbol: "star.fill",
                    label: "Favorites",
                    value: favoriteCourtsText,
                    placeholder: "None starred yet"
                )

                ProfileRow(
                    symbol: "location.circle.fill",
                    label: "Search Radius",
                    value: viewModel.preferredRadiusText,
                    placeholder: viewModel.defaultRadiusText,
                    detail: "around you",
                    onTap: { viewModel.beginEditing(.preferredRadius) }
                )
            }

            section("Account") {
                ProfileRow(
                    symbol: "person.fill",
                    label: "Username",
                    value: viewModel.userName,
                    placeholder: "Not set",
                    onTap: { viewModel.beginEditing(.userName) }
                )

                // Read-only: email belongs to Firebase Auth, and changing it
                // needs a re-authentication flow this screen doesn't have yet.
                ProfileRow(
                    symbol: "envelope.fill",
                    label: "Email",
                    value: viewModel.email,
                    placeholder: "Not set"
                )

                // The value is a stand-in, not the password: Firebase Auth
                // stores a hash and this app never sees one, so there is
                // nothing real to render. Tapping sends a reset link rather
                // than opening a field — and goes read-only when there's no
                // address to send to.
                ProfileRow(
                    symbol: "lock.fill",
                    label: "Password",
                    value: "••••••••",
                    placeholder: "••••••••",
                    onTap: viewModel.canChangePassword ? {
                        viewModel.beginChangingPassword()
                        isChangingPassword = true
                    } : nil
                )

                // Device-local, not part of the profile document — see
                // `AppearancePreference`. It sits among the stored fields
                // because this is where a user looks for a setting, not
                // because it shares their storage.
                ProfileRow(
                    symbol: appearance.symbolName,
                    label: "Appearance",
                    value: appearance.title,
                    placeholder: AppearancePreference.system.title,
                    onTap: { isEditingAppearance = true }
                )

                // Immutable by design — `createdAt` is write-once server-side.
                ProfileRow(
                    symbol: "calendar",
                    label: "Joined",
                    value: viewModel.dateJoinedText,
                    placeholder: "—"
                )
            }

            // The end of the list, not a bar of its own: the rows already run
            // to the bottom of the screen, and a pinned bar over them would be
            // a permanent reminder of the one action nobody comes here for.
            ProfileActionRow(
                symbol: "rectangle.portrait.and.arrow.right",
                title: "Sign Out",
                tint: .hooprRed
            ) {
                viewModel.signOut()
            }
            .padding(.top, 4)
        }
    }

    /// Count and unit as one value — "12 courts" — rather than a value with a
    /// unit hung off it. `nil` at zero, which renders the placeholder.
    private var favoriteCourtsText: String? {
        guard let count = viewModel.favoriteCourtCountText else { return nil }
        return "\(count) \(viewModel.favoriteCourtUnitText)"
    }

    /// A titled group of rows, using the same section heading as the Local Runs
    /// tab so the two screens read as one app.
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            Text(title)
                .hooprFont(18, weight: .bold)
                .foregroundStyle(Color.hooprPrimaryText)
                .padding(.bottom, 2)

            content()
        }
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
        friendService: FriendService(authService: authService),
        onBack: {}
    )
}
