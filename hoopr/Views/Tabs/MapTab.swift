import SwiftUI
import MapKit

/// The sheet's two layout inputs, read together so one `onGeometryChange` can
/// deliver both without either lagging a frame behind the other.
///
/// Declared outside `MapTab` and explicitly `nonisolated` because
/// `onGeometryChange` requires a `Sendable` value: nested in the view — or
/// left to this module's default main-actor isolation — its `Equatable`
/// conformance is actor-isolated and can't satisfy that.
private nonisolated struct SheetMetrics: Equatable {
    var height: CGFloat
    var bottomInset: CGFloat
}

struct MapTab: View {
    @StateObject private var viewModel: FindAMatchViewModel
    @State private var recenterTrigger: RecenterTrigger?
    @State private var sheetState: SheetState = .rest(.medium)

    /// The court a run is being started at, if the form is open. Both entry
    /// points — a map pin and a nearby-list row — open the same detail card, so
    /// one button there covers both without duplicating a control.
    @State private var startingRunAt: Court?

    /// Live finger travel for the sheet drag; zero whenever the sheet is settled.
    @State private var sheetDrag: CGFloat = 0
    /// How far the court list has scrolled — the sheet only takes over a drag
    /// that starts at the top.
    @State private var listScrollOffset: CGFloat = 0

    /// The height the sheet is allowed to use — the tab's own height *minus*
    /// the tab bar. The detents are fractions of it. Seeded with a typical
    /// phone height so the first frame renders a sensibly sized sheet before
    /// geometry lands; this also avoids `UIScreen.main`, deprecated in iOS 26.
    @State private var containerHeight: CGFloat = 852

    /// How far the tab bar reaches up from the bottom edge.
    ///
    /// Load-bearing, and not something the layout gets for free: `MapView`
    /// ignores the safe area so the map can run under the bar, and that makes
    /// the whole `ZStack` full-height. Without subtracting this the sheet is
    /// sized and positioned against a screen that is taller than the one the
    /// user can reach, and its last rows render underneath the tab bar.
    @State private var tabBarInset: CGFloat = 0

    /// A court handed in from Home's hot list. Consumed on arrival and written
    /// back to `nil`, so selecting the same court twice works.
    @Binding var courtToSelect: Court?

    /// Whether the search field has the keyboard.
    ///
    /// Load-bearing beyond the field itself: it drops the chip row, raises the
    /// sheet, swaps the sheet's contents, and hides the recenter button — see
    /// each of those for why.
    @FocusState private var isSearchFocused: Bool

    /// The run awaiting a cancel confirmation, if any.
    ///
    /// Cancelling destroys everyone else's spot, so it asks first — the same
    /// bar `GameCard` sets on the Runs tab. Held as state rather than a
    /// per-row flag so the dialog survives the row being rebuilt by a snapshot
    /// arriving mid-confirmation.
    @State private var runPendingCancel: Game?

    /// Where the sheet was resting before search took it to `.expanded`, so
    /// dismissing the keyboard puts it back rather than stranding it open.
    @State private var detentBeforeSearch: SheetDetent?

    /// Whether the map has already moved to the device's first fix. Guards a
    /// one-shot: `initialFix` only publishes once, but a view can be re-created
    /// while the view model survives, and re-applying the trigger would yank
    /// the map back after the user had panned away.
    @State private var hasAppliedInitialFix = false

    /// Gap kept below the sheet's own content, and under the collapsed pill, so
    /// neither sits beneath the home indicator.
    ///
    /// Smaller than it was: the tab bar now occupies the bottom of the screen
    /// and the sheet is laid out above it, so this no longer has to clear the
    /// home indicator on its own.
    private let peekBottomInset: CGFloat = 12
    /// Finger travel below which a handle drag counts as a tap instead.
    private let tapSlop: CGFloat = 6

    private let gameService: GameService

    /// Observed because `ProfileButton` reads it for its badge dot.
    @ObservedObject private var friendService: FriendService

    /// Handed up rather than handled here — opening the profile replaces the
    /// whole interface, which is the shell's call to make, not a tab's.
    private let onOpenProfile: () -> Void

    init(
        courtService: CourtService,
        locationService: LocationService,
        userProfileService: UserProfileService,
        gameService: GameService,
        recentCourtsStore: RecentCourtsStore,
        friendService: FriendService,
        courtToSelect: Binding<Court?>,
        onOpenProfile: @escaping () -> Void
    ) {
        self.gameService = gameService
        self.friendService = friendService
        self.onOpenProfile = onOpenProfile
        _courtToSelect = courtToSelect
        _viewModel = StateObject(wrappedValue: FindAMatchViewModel(
            courtService: courtService,
            locationService: locationService,
            userProfileService: userProfileService,
            gameService: gameService,
            recentCourtsStore: recentCourtsStore
        ))
    }

    // MARK: - Detent geometry

    /// All of the sheet's arithmetic, rebuilt whenever the container resizes.
    /// The view keeps the state and the gestures; `SheetGeometry` does the maths.
    private var geometry: SheetGeometry {
        SheetGeometry(containerHeight: containerHeight)
    }

    private var mediumHeight: CGFloat { geometry.mediumHeight }

    private var sheetHeight: CGFloat {
        geometry.sheetHeight(detent: sheetState.displayDetent, drag: sheetDrag)
    }

    private var sheetOffset: CGFloat {
        geometry.sheetOffset(detent: sheetState.displayDetent, drag: sheetDrag)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            MapView(
                courts: viewModel.courts,
                initialRegion: viewModel.initialRegion,
                recenterTrigger: $recenterTrigger,
                gameCountByCourtID: viewModel.gameCountByCourtID,
                selectedCourtID: sheetState.selectedCourt?.id,
                onMarkerTap: { court in
                    select(court)
                },
                onMarkerDeselect: {
                    dismissDetail()
                }
            )
            // The map is the screen, not a panel on it — it runs under the
            // status bar, the floating header, and the home indicator.
            .ignoresSafeArea()

            mapOverlay

            recenterButton

            sheet

            collapsedPeek
        }
        .onGeometryChange(for: SheetMetrics.self) { proxy in
            SheetMetrics(height: proxy.size.height, bottomInset: proxy.safeAreaInsets.bottom)
        } action: { metrics in
            tabBarInset = metrics.bottomInset

            let usable = metrics.height - metrics.bottomInset
            if usable > 0 { containerHeight = usable }
        }
        // A court arriving from Home's hot list. Cleared immediately so the
        // same court can be sent again, and routed through the same
        // `select(_:recenter:)` a list row uses rather than reaching into the
        // sheet's state machine.
        .onChange(of: courtToSelect) { _, court in
            guard let court else { return }
            courtToSelect = nil
            select(court, recenter: true)
        }
        // The device's first fix, applied once and never over a selection — a
        // map that yanks itself out from under a court you just tapped is
        // worse than one still centred on Durham.
        //
        // `onReceive` rather than `onChange`: the latter needs `Equatable`, and
        // `CLLocationCoordinate2D` isn't — conforming a CoreLocation type
        // app-side to satisfy a view modifier would be the tail wagging the dog.
        // Focus raises the sheet to meet the keyboard; blur puts it back where
        // it was. Without the stash, dismissing the keyboard would leave the
        // sheet stranded at full height over a map the user can no longer see.
        .onChange(of: isSearchFocused) { _, focused in
            if focused {
                if detentBeforeSearch == nil {
                    detentBeforeSearch = sheetState.detent
                }
                settle(to: .expanded)
            } else if let previous = detentBeforeSearch {
                detentBeforeSearch = nil
                // A query left in the field keeps the results on screen, so the
                // sheet stays up until it's actually cleared.
                if !viewModel.hasSearchQuery {
                    settle(to: previous)
                }
            }
        }
        // Clearing the field while unfocused is the other way out of search.
        .onChange(of: viewModel.searchQuery) { _, query in
            guard query.isEmpty, !isSearchFocused, let previous = detentBeforeSearch else { return }
            detentBeforeSearch = nil
            settle(to: previous)
        }
        .onReceive(viewModel.$initialFix) { fix in
            guard let fix,
                  !hasAppliedInitialFix,
                  sheetState.selectedCourt == nil
            else { return }
            hasAppliedInitialFix = true
            recenterTrigger = RecenterTrigger(center: fix)
        }
        .confirmationDialog(
            "Cancel this run?",
            isPresented: Binding(
                get: { runPendingCancel != nil },
                set: { if !$0 { runPendingCancel = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Cancel run", role: .destructive) {
                guard let game = runPendingCancel else { return }
                runPendingCancel = nil
                Task { await viewModel.perform(.cancel, on: game) }
            }
            Button("Keep it", role: .cancel) { runPendingCancel = nil }
        } message: {
            Text("Everyone on the roster loses their spot. This can't be undone.")
        }
        .sheet(item: $startingRunAt) { court in
            CreateGameSheet(
                court: court,
                gameService: gameService,
                onCreated: {
                    startingRunAt = nil
                    // The run lands in Local Runs on the listener that's
                    // already open; the map has nothing to update.
                },
                onCancel: { startingRunAt = nil }
            )
        }
    }

    // MARK: - Map chrome

    /// Search and the filter chips, floating over the map on glass.
    ///
    /// Two rows, not three. The profile button used to occupy a whole row on
    /// its own; folding it into the search row is what pays for the search
    /// field without costing the map any height. (It doesn't *gain* height
    /// either — the honest total is 4pt shorter than before. What changes is
    /// that the top row stops being decoration and becomes the screen's
    /// primary control.)
    ///
    /// The trailing `Spacer` is load-bearing: it holds the stack at full
    /// height so the rows stay pinned to the top of a `ZStack` that aligns its
    /// children to the bottom.
    private var mapOverlay: some View {
        VStack(alignment: .trailing, spacing: 10) {
            searchRow

            // Dropped while typing. This is a layout requirement, not a
            // preference: the keyboard takes the bottom safe area, which
            // shrinks `containerHeight` and pushes the sheet up until the
            // overlay has roughly 95pt to work with. Two rows need ~106pt and
            // would be clipped; one fits with room to spare.
            if !isSearchFocused {
                filterChips
            }

            Spacer()
        }
        // The map runs under the status bar; its chrome starts below it.
        .padding(.top, 8)
        // Keep the chrome clear of the sheet, whatever height it's at — and of
        // the tab bar, which the sheet now sits on top of.
        .padding(.bottom, max(0, sheetHeight - sheetOffset) + tabBarInset)
        .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            HooprSearchField(
                text: $viewModel.searchQuery,
                placeholder: "Search courts or a city",
                isFocused: $isSearchFocused,
                ground: .glass,
                // Court and city names are proper nouns.
                capitalization: .words,
                onClear: { viewModel.clearSearch() }
            )

            ProfileButton(
                friendService: friendService,
                style: .glass,
                action: onOpenProfile
            )
        }
        .padding(.horizontal, 14)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CourtFilter.allCases) { filter in
                    GlassChip(
                        symbolName: filter.symbolName,
                        label: filter.label,
                        isActive: viewModel.isActive(filter)
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.toggle(filter)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        // Full width now that the recenter button has moved down to the thumb
        // zone, so a long row of chips scrolls under the screen edge rather
        // than stopping short of a control.
    }

    /// The only map control left, and it now floats bottom-right rather than
    /// sharing the chip row.
    ///
    /// Recenter is a frequent, casual tap; the top of a 6.7" phone is the part
    /// you can't reach one-handed. Sitting just above the sheet puts it in the
    /// thumb zone and matches where every other map app keeps it — and it
    /// hands the chips back the ~60pt of width it was taking.
    ///
    /// There used to be a `+`/`−` pair with a vertical slider between them. It
    /// occupied a 44×180pt column of the map to duplicate a pinch every user
    /// already knows, and it was the single most dated thing on the screen —
    /// so the whole stack is gone, along with the absolute/stepped zoom
    /// triggers and the log-scale span conversion that fed it.
    private var recenterButton: some View {
        // Hidden at the expanded detent. Its inset would put it above the
        // chrome's bottom edge — on top of the filter chips — and at that
        // detent the visible map is a sliver anyway.
        let isHidden = sheetState.displayDetent == .expanded || isSearchFocused

        return VStack {
            Spacer()

            Button {
                recenterMap()
            } label: {
                Image(systemName: "location.fill")
                    .hooprFont(17, weight: .semibold, maximumSize: 20)
                    .foregroundStyle(Color.hooprOrange)
                    .frame(width: 46, height: 46)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Recenter map")
            .accessibilityHidden(isHidden)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 14)
        .padding(.bottom, max(0, sheetHeight - sheetOffset) + tabBarInset + peekBottomInset)
        .opacity(isHidden ? 0 : 1)
        .allowsHitTesting(!isHidden)
        .animation(.easeInOut(duration: 0.2), value: isHidden)
    }

    // MARK: - Sheet

    /// One continuous surface whose contents swap between the court list and a
    /// selected court's detail card.
    ///
    /// Deliberately *not* glass: the chrome floating over the map is glass
    /// because it's small and you look past it, but a list of courts is
    /// something you read, and reading it against a moving map is worse in
    /// every way than reading it against a surface.
    private var sheet: some View {
        Group {
            // Search outranks both: focusing the field is an explicit request
            // for it, and it would be strange for a detail card opened earlier
            // to keep the surface while the user is typing.
            if isSearchFocused || viewModel.hasSearchQuery {
                searchPane
                    .transition(.opacity)
            } else if let court = sheetState.selectedCourt {
                courtCard(court: court)
                    .transition(.opacity)
            } else {
                courtList
                    .transition(.opacity)
            }
        }
        // The content stops above the tab bar — a list you read can't run
        // under it — but the surface behind it does not. The tab bar floats
        // with transparent margins, so a sheet that ended where its content
        // does would show a band of map between the two.
        .frame(height: sheetHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .fill(Color.hooprSurface)
                .shadow(color: Color.hooprShadow(opacity: 0.08), radius: 12, x: 0, y: -4)
                .frame(height: sheetHeight + tabBarInset)
        }
        .offset(y: sheetOffset)
        .padding(.bottom, tabBarInset)
    }

    /// All that's left once the sheet is dismissed — a compact tap target that
    /// fades in over the back half of the drag as the sheet clears the screen.
    private var collapsedPeek: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.up")
                .hooprFont(11, weight: .semibold)

            Text(viewModel.listCountLabel)
                .hooprFont(13, weight: .semibold)
        }
        .foregroundStyle(Color.hooprPrimaryText)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular.interactive(), in: .capsule)
        .contentShape(Capsule())
        .gesture(sheetDragGesture(fromHandle: true))
        .padding(.bottom, peekBottomInset + tabBarInset)
        .opacity(peekOpacity)
        .allowsHitTesting(peekOpacity > 0.5)
    }

    /// Held at zero until the sheet is most of the way gone, so the pill never
    /// competes with the sheet it replaces.
    private var peekOpacity: Double {
        guard sheetState.selectedCourt == nil, mediumHeight > 0 else { return 0 }
        let progress = min(max(sheetOffset / mediumHeight, 0), 1)
        return Double(min(max((progress - 0.6) / 0.4, 0), 1))
    }

    private var courtList: some View {
        VStack(spacing: 0) {
            sheetHeader
                .gesture(sheetDragGesture(fromHandle: true))

            listTabs

            if viewModel.isCurrentListEmpty {
                emptyState
            } else if viewModel.selectedTab == .now {
                activeList
            } else {
                nearbyList
            }
        }
    }

    /// The sheet while search has it: matches for the query, or recent courts
    /// before anything is typed.
    ///
    /// Recent lives here rather than as a fourth segment — the standard iOS
    /// home for it, and it means an empty search field is useful instead of
    /// blank.
    private var searchPane: some View {
        VStack(spacing: 0) {
            sheetHandle
                .gesture(sheetDragGesture(fromHandle: true))

            Text(viewModel.searchHeaderLabel)
                .hooprFont(12, weight: .bold, maximumSize: 16)
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Color.hooprSecondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            if searchPaneCourts.isEmpty {
                searchEmptyState
            } else {
                sheetScroll {
                    ForEach(searchPaneCourts) { court in
                        Button {
                            selectFromSearch(court)
                        } label: {
                            searchResultRow(court)
                        }
                        .buttonStyle(.plain)

                        rowDivider
                    }
                }
                // The list is the keyboard's dismiss gesture. iOS users are
                // trained on it, and it's the one dismissal that doesn't
                // compete with the map's own tap handling.
                .scrollDismissesKeyboard(.immediately)
            }
        }
    }

    private var searchPaneCourts: [Court] {
        viewModel.hasSearchQuery ? viewModel.searchResults : viewModel.recentCourts
    }

    private func searchResultRow(_ court: Court) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(court.displayName)
                    .hooprFont(16, weight: .semibold)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .lineLimit(1)

                Text("\(court.city) · \(viewModel.distanceText(for: court)) away")
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var searchEmptyState: some View {
        VStack(spacing: 6) {
            Spacer()

            Text(viewModel.hasSearchQuery ? "No courts match" : "No recent courts")
                .hooprFont(15, weight: .semibold)
                .foregroundStyle(Color.hooprPrimaryText)

            Text(
                viewModel.hasSearchQuery
                    ? "Try a court name, or the town it's in."
                    : "Courts you open will show up here."
            )
            .hooprFont(13)
            .foregroundStyle(Color.hooprSecondaryText)
            .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }

    /// Picking a result closes search entirely — the query is cleared, not just
    /// unfocused, so the sheet returns to its segments instead of sitting on a
    /// stale result list behind the court you just opened.
    private func selectFromSearch(_ court: Court) {
        isSearchFocused = false
        viewModel.clearSearch()
        select(court, recenter: true)
    }

    /// The **Now** segment: courts with a run on today.
    ///
    /// Rows carry no Join/Leave button. Tapping one does exactly what a court
    /// row does — opens the detail card — which is the single place either this
    /// tab or the Runs tab acts on a run. The Runs tab is where a run is
    /// *managed*; this is where one is *found*.
    private var activeList: some View {
        sheetScroll {
            ForEach(viewModel.activeCourts) { active in
                Button {
                    select(active.court, recenter: true)
                } label: {
                    CourtGameRow(activeCourt: active)
                }
                .buttonStyle(.plain)

                rowDivider
            }
        }
    }

    /// The **Nearby** and **Saved** segments, which both list plain courts.
    private var nearbyList: some View {
        sheetScroll {
            ForEach(viewModel.listedCourts) { nearby in
                Button {
                    select(nearby.court, recenter: true)
                } label: {
                    CourtRow(
                        nearbyCourt: nearby,
                        isFavorite: viewModel.isFavorite(nearby.court),
                        onToggleFavorite: {
                            viewModel.toggleFavorite(nearby.court)
                        }
                    )
                }
                .buttonStyle(.plain)

                rowDivider
            }
        }
    }

    private var rowDivider: some View {
        Divider()
            .overlay(Color.hooprBorder)
            .padding(.leading, 20)
    }

    /// The sheet's one scrolling container.
    ///
    /// Every list goes through this rather than building its own, because the
    /// three modifiers below are what arbitrate between scrolling the list and
    /// dragging the sheet — and a second hand-rolled copy of that arbitration
    /// is exactly how the two gestures start fighting.
    private func sheetScroll<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                content()
            }
            .padding(.bottom, peekBottomInset + tabBarInset)
        }
        .scrollDisabled(sheetDrag != 0)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { _, offset in
            listScrollOffset = offset
        }
        .simultaneousGesture(sheetDragGesture(fromHandle: false))
    }

    /// Now / Nearby / Saved. Switching only changes which courts the sheet
    /// lists — the map and its filters are unaffected.
    private var listTabs: some View {
        HStack(spacing: 0) {
            ForEach(FindAMatchViewModel.ListTab.allCases) { tab in
                let isSelected = viewModel.selectedTab == tab

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 7) {
                        // Three tabs divide one row evenly, so the labels
                        // shrink to fit rather than wrapping into each other
                        // at the accessibility sizes.
                        Text(tab.title)
                            .hooprFont(13, weight: isSelected ? .bold : .medium, maximumSize: 17)
                            .foregroundStyle(isSelected ? Color.hooprPrimaryText : Color.hooprSecondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Rectangle()
                            .fill(isSelected ? Color.hooprOrange : Color.hooprBorder)
                            .frame(height: isSelected ? 2 : 1)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Shown when the current segment has nothing in it.
    ///
    /// The `.now` segment gets a button, the others don't. With no runs booked
    /// anywhere, an empty Now list is the most common state this tab has — and
    /// the only lever the interface has on that cold start is to make starting
    /// a run the obvious next move rather than apologising for the emptiness.
    /// Follows `HomeTab`'s `noRunCard`, which answers the same problem.
    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()

            if viewModel.selectedTab == .now, viewModel.datasetError == nil {
                Image(systemName: "basketball.fill")
                    .hooprFont(30, maximumSize: 40)
                    .foregroundStyle(Color.hooprSecondaryText.opacity(0.45))
                    .padding(.bottom, 4)
            }

            Text(viewModel.emptyStateTitle)
                .hooprFont(15, weight: .semibold)
                .foregroundStyle(Color.hooprPrimaryText)

            if let detail = viewModel.emptyStateDetail {
                Text(detail)
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .multilineTextAlignment(.center)
            }

            // Only when there's somewhere to send them. Filters or a failed
            // dataset can leave no court to start at, and a button that can't
            // act is worse than no button.
            if viewModel.selectedTab == .now,
               viewModel.datasetError == nil,
               let court = viewModel.nearestCourtForNewRun {
                Button {
                    startingRunAt = court
                } label: {
                    Text("Start a run")
                        .hooprFont(15, weight: .semibold, maximumSize: 22)
                        .foregroundStyle(Color.hooprOnBrand)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.hooprOrange)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }

    /// The bare grab handle.
    private var sheetHandle: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color.hooprBorder)
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .contentShape(Rectangle())
    }

    /// Drag handle plus court count — the only part left visible when collapsed.
    ///
    /// The count belongs to the *segments*, so the search pane uses
    /// `sheetHandle` instead: "116 courts nearby" sitting above a RECENT list
    /// describes neither of the two things on screen.
    private var sheetHeader: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.hooprBorder)
                .frame(width: 36, height: 5)

            Text(viewModel.listCountLabel)
                .hooprFont(13, weight: .medium)
                .foregroundStyle(Color.hooprSecondaryText)
        }
        .padding(.top, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    /// The selected court, led by what's happening there.
    ///
    /// Restructured from a card that opened with amenity badges. On a tab whose
    /// job is "find a game right now", the runs are the headline and the
    /// surface material is the footnote — so today's runs come first and
    /// `CourtBadges` moves below them.
    ///
    /// Three bands, and the split is load-bearing at the `.medium` detent,
    /// where the sheet has ~256pt: a fixed header, a **scrolling** middle, and
    /// a **pinned** action row. Letting the whole card scroll would put "Start
    /// Run" below the fold — you'd have to scroll to find the primary action on
    /// a screen that exists to start runs.
    @ViewBuilder
    private func courtCard(court: Court) -> some View {
        let games = viewModel.gamesToday(at: court)

        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.hooprBorder)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 14)
                .contentShape(Rectangle())
                .gesture(sheetDragGesture(fromHandle: true))

            cardHeader(court: court)
                .padding(.horizontal, 20)

            // Scrolls, so a court with three runs is reachable by dragging the
            // sheet up rather than by the card growing past its detent.
            sheetScroll {
                VStack(alignment: .leading, spacing: 10) {
                    if games.isEmpty {
                        noRunsToday
                    } else {
                        ForEach(games) { game in
                            runRow(game)
                        }
                    }

                    CourtBadges(court: court)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                // `sheetScroll`'s stack centres its children, which is right
                // for full-width rows and wrong for this card — without it the
                // copy floats mid-sheet while the header above it is flush left.
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            cardActions(court: court, hasRuns: !games.isEmpty)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cardHeader(court: Court) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "basketball.fill")
                .foregroundStyle(Color.hooprOrange)
                .hooprFont(20)

            VStack(alignment: .leading, spacing: 3) {
                Text(court.displayName)
                    .hooprFont(17, weight: .semibold)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .lineLimit(2)

                Text("\(court.city) · \(viewModel.distanceText(for: court)) away")
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)
            }

            Spacer(minLength: 8)

            Button {
                viewModel.toggleFavorite(court)
            } label: {
                Image(systemName: viewModel.isFavorite(court) ? "star.fill" : "star")
                    .hooprFont(19)
                    .foregroundStyle(
                        viewModel.isFavorite(court) ? Color.hooprOrange : Color.hooprSecondaryText
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isFavorite(court) ? "Remove favorite" : "Add favorite")

            Button {
                dismissDetail()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .hooprFont(24)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    /// One run at this court, with the button that acts on it.
    ///
    /// This is the only place either the map or the Runs tab performs a roster
    /// action from — which is why the Now segment's rows carry no buttons of
    /// their own and route here instead.
    private func runRow(_ game: Game) -> some View {
        let action = viewModel.action(for: game)
        let isPending = viewModel.pendingGameId == game.id
        let isBlocked = viewModel.pendingGameId != nil && !isPending

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(game.scheduledText())
                    .hooprFont(14, weight: .semibold)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .lineLimit(1)

                Text(game.rosterText)
                    .hooprFont(12)
                    .foregroundStyle(Color.hooprSecondaryText)
            }

            Spacer(minLength: 8)

            if action != .none {
                Button {
                    if action == .cancel {
                        runPendingCancel = game
                    } else {
                        Task { await viewModel.perform(action, on: game) }
                    }
                } label: {
                    Group {
                        if isPending {
                            ProgressView()
                                .tint(action.isDestructive ? Color.hooprRed : Color.hooprOnBrand)
                        } else {
                            Text(action.title)
                                .hooprFont(13, weight: .semibold, maximumSize: 18)
                        }
                    }
                    .foregroundStyle(action.isDestructive ? Color.hooprRed : Color.hooprOnBrand)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(action.isDestructive ? Color.hooprFill : Color.hooprOrange)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isPending || isBlocked)
                .opacity(isBlocked ? 0.5 : 1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardChrome(cornerRadius: 12)
    }

    private var noRunsToday: some View {
        Text("No runs here today.")
            .hooprFont(13)
            .foregroundStyle(Color.hooprSecondaryText)
    }

    /// Start Run is primary and Directions secondary, reversing the old order.
    ///
    /// Getting there is a solved problem every phone already has an app for;
    /// putting a run on the board is the thing only this app does, and the one
    /// the cold-start problem depends on.
    private func cardActions(court: Court, hasRuns: Bool) -> some View {
        HStack(spacing: 10) {
            Button {
                openDirections(to: court)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .hooprFont(14, weight: .semibold, maximumSize: 20)
                    Text("Directions")
                        .hooprFont(15, weight: .semibold, maximumSize: 22)
                }
                .foregroundStyle(Color.hooprPrimaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.hooprFill)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Button {
                startingRunAt = court
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .hooprFont(14, weight: .semibold, maximumSize: 20)
                    Text(hasRuns ? "Add a run" : "Start Run")
                        .hooprFont(15, weight: .semibold, maximumSize: 22)
                        .lineLimit(1)
                }
                .foregroundStyle(Color.hooprOnBrand)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.hooprOrange)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    /// Hands the court to Maps for routing. The app knows where its courts are
    /// but nothing about how to get to one, and every phone already has a
    /// router on it.
    private func openDirections(to court: Court) {
        let item = MKMapItem(
            location: CLLocation(latitude: court.latitude, longitude: court.longitude),
            address: court.address.isEmpty
                ? nil
                : MKAddress(fullAddress: court.address, shortAddress: nil)
        )
        item.name = court.displayName
        item.openInMaps(
            launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
        )
    }

    // MARK: - Sheet position

    private func sheetDragGesture(fromHandle: Bool) -> some Gesture {
        DragGesture(minimumDistance: fromHandle ? 0 : 8)
            .onChanged { value in
                // Inside the list the sheet only claims a downward drag that
                // begins at the top; everything else stays list scrolling.
                if !fromHandle, sheetDrag == 0 {
                    guard listScrollOffset <= 1, value.translation.height > 0 else { return }
                }
                sheetDrag = value.translation.height
            }
            .onEnded { value in
                let target: SheetDetent

                if fromHandle, abs(value.translation.height) < tapSlop {
                    // Barely moved, so treat it as a tap on the handle: step
                    // between medium and collapsed.
                    target = sheetState.detent == .collapsed ? .medium : .collapsed
                } else {
                    // Project the fling so a quick flick settles the same way a
                    // long drag does.
                    target = SheetGeometry.nextDetent(
                        from: sheetState.detent,
                        projecting: value.predictedEndTranslation.height
                    )
                }

                sheetDrag = 0
                // While the keyboard is up `mediumHeight` is roughly 140pt and
                // `.collapsed` would put the sheet off-screen behind it, with
                // no way back except dismissing a keyboard the user can no
                // longer see a field for. Search owns the sheet until it's
                // dismissed.
                settle(to: isSearchFocused && target == .collapsed ? .medium : target)
            }
    }

    private func settle(to detent: SheetDetent) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            switch sheetState {
            case .rest:
                sheetState = .rest(detent)
            case .detail(let court, _):
                sheetState = .detail(court: court, returningTo: detent)
            }
        }
    }

    // MARK: - Selection

    private func select(_ court: Court, recenter: Bool = false) {
        viewModel.select(court)
        if recenter {
            recenterTrigger = RecenterTrigger(center: court.coordinate)
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            // Detail reads best at the medium detent — expanded leaves a card
            // stranded in whitespace.
            let fallback: SheetDetent = sheetState.detent == .collapsed ? .collapsed : .medium
            sheetState = .detail(court: court, returningTo: fallback)
        }
    }

    private func dismissDetail() {
        guard sheetState.selectedCourt != nil else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            sheetState = .rest(sheetState.detent)
        }
    }

    private func recenterMap() {
        recenterTrigger = RecenterTrigger(center: viewModel.recenterTarget())
    }
}

#Preview {
    @Previewable @State var courtToSelect: Court?
    let authService = AuthService()

    MapTab(
        courtService: CourtService(),
        locationService: LocationService(),
        userProfileService: UserProfileService(authService: authService),
        gameService: GameService(authService: authService),
        recentCourtsStore: RecentCourtsStore(),
        friendService: FriendService(authService: authService),
        courtToSelect: $courtToSelect,
        onOpenProfile: {}
    )
}
