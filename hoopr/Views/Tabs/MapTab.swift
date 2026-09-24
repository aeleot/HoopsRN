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
    /// Counts runs this screen has started, for the success haptic.
    @State private var runsStarted = 0

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

    /// The unsafe band `onGeometryChange` reports at the bottom of this tab's
    /// own frame — which is already laid out net of the tab bar, the same as
    /// every other tab's content. At rest this is a few points of residual
    /// margin; once the keyboard is up it's the keyboard's height. It feeds
    /// `containerHeight` and the chrome that has to clear the keyboard
    /// (`mapOverlay`, `recenterButton`) — it is not what positions the sheet
    /// or the collapsed pill against the tab bar, since the frame's own
    /// bottom edge already is that position.
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

    /// The height of the selected court card's lead — its header and its first
    /// run — as last laid out. Feeds `SheetGeometry.fittedMediumHeight`, so the
    /// card rests tall enough to show a run whole. See `cardFittedHeight`.
    @State private var cardLeadHeight: CGFloat = 0

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

    /// Same reason as `friendService` — `ProfileButton`'s badge also carries
    /// squad invites now.
    @ObservedObject private var squadService: SquadService

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
        squadService: SquadService,
        courtToSelect: Binding<Court?>,
        onOpenProfile: @escaping () -> Void
    ) {
        self.gameService = gameService
        self.friendService = friendService
        self.squadService = squadService
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
        SheetGeometry(
            containerHeight: containerHeight,
            fittedMediumHeight: sheetState.selectedCourt == nil ? nil : cardFittedHeight
        )
    }

    /// What the court card needs at `.medium`: its fixed handle and action row,
    /// the lead it measured (header, then the first run or "No runs here
    /// today"), and a gap so the row isn't flush against the buttons. A court
    /// with nothing but a name fits the plain medium height and keeps it.
    private var cardFittedHeight: CGFloat? {
        guard cardLeadHeight > 0 else { return nil }
        return Self.cardHandleHeight + Self.cardScrollTopInset + cardLeadHeight
            + Spacing.md + Self.cardActionsHeight
    }

    /// The court card's fixed chrome, named so the view and the arithmetic
    /// above can't drift: the grab handle (10 + 5 + 14) and the pinned action
    /// row (10 + 48 + 14). The buttons are a fixed 48pt; their labels cap.
    private static let cardHandleHeight: CGFloat = 10 + 5 + 14
    private static let cardScrollTopInset: CGFloat = 2
    private static let cardActionsHeight: CGFloat = 10 + 48 + 14

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
            // The map runs under the status bar and the floating chrome — but
            // *not* under the tab bar. Stopping it at the container's bottom
            // edge is what leaves the bar sitting on this tab's own surface
            // (below) instead of on moving map, which is how Home and Runs get
            // a solid bar and why theirs never flickers: nothing about it is
            // computed from a gesture.
            //
            // `.keyboard` stays ignored on every edge. The map is not laid out
            // around the keyboard — only the chrome is — and a map that
            // resized itself each time the search field took focus would lurch
            // under the user's thumb.
            .ignoresSafeArea(.container, edges: [.top, .horizontal])
            .ignoresSafeArea(.keyboard)

            mapOverlay

            recenterButton

            sheet

            collapsedPeek
        }
        // The ground the tab bar reads against. The map stops at the bar's top
        // edge (above), so this is what fills the band the bar floats in —
        // always there, never animated, exactly the way the Runs tab's own
        // background is what makes its bar solid. `hooprSurface` rather than
        // `hooprBackground` because in dark mode the band continues the sheet
        // resting on it; in light mode the two are the same white.
        .background(Color.hooprSurface.ignoresSafeArea())
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
                onCancel: { startingRunAt = nil },
                onConfirmed: { runsStarted += 1 }
            )
        }
        // Here rather than in the sheet: a public run dismisses it in the same
        // update the write confirms in (UI revamp Phase 3).
        .sensoryFeedback(.success, trigger: runsStarted)
        .sensoryFeedback(trigger: viewModel.lastConfirmation) { _, new in
            new?.kind.feedback
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
        // The map runs under the status bar; its chrome starts below it — at
        // whatever height centres the search row on the profile button's slot,
        // so the button is where every other tab has it.
        .padding(.top, ProfileButton.Slot.centerY - Self.searchFieldHeight / 2)
        // Keep the chrome clear of the sheet, whatever height it's at — and of
        // the tab bar, which the sheet now sits on top of.
        .padding(.bottom, max(0, sheetHeight - sheetOffset) + tabBarInset)
        .animation(.hooprSpring, value: isSearchFocused)
    }

    /// Named because the chrome's top inset is computed from it.
    private static let searchFieldHeight: CGFloat = 46

    /// The field keeps the map chrome's 14pt inset on the leading side; the
    /// trailing side takes the page margin every tab has, so the profile
    /// button lands where it does on Home, Runs and Seasons.
    private var searchRow: some View {
        HStack(spacing: 10) {
            HooprSearchField(
                text: $viewModel.searchQuery,
                placeholder: "Search courts or a city",
                isFocused: $isSearchFocused,
                ground: .glass,
                height: Self.searchFieldHeight,
                // Court and city names are proper nouns.
                capitalization: .words,
                onClear: { viewModel.clearSearch() }
            )

            ProfileButton(friendService: friendService, squadService: squadService, action: onOpenProfile)
        }
        .padding(.leading, 14)
        .padding(.trailing, Spacing.pageMargin)
    }

    /// One `HooprGlassGroup`, so the chips are rendered as one row of glass
    /// rather than three pieces sampling the map separately (UI revamp
    /// Phase 4). Inside the scroll view, because the group has to contain the
    /// shapes it groups.
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HooprGlassGroup {
                HStack(spacing: 8) {
                    ForEach(CourtFilter.allCases) { filter in
                        GlassChip(
                            symbolName: filter.symbolName,
                            label: filter.label,
                            isActive: viewModel.isActive(filter)
                        ) {
                            withAnimation(.hooprSnap) {
                                viewModel.toggle(filter)
                            }
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
    /// you can't reach one-handed. Resting directly above the tab bar — the
    /// same low baseline `collapsedPeek` sits on — puts it in the thumb zone
    /// and matches where every other map app keeps it, rather than floating
    /// it wherever the sheet's *default* detent happens to put it. It hands
    /// the chips back the ~60pt of width it was taking, too.
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
                    .foregroundStyle(Color.hooprBrandAccent)
                    .frame(width: 46, height: 46)
                    .hooprGlass(in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Recenter map")
            .accessibilityHidden(isHidden)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 14)
        // No `tabBarInset` here, deliberately — this tab's own frame is
        // already laid out net of the tab bar (see `body`), so the container's
        // bottom edge *is* the tab bar's top edge. `peekBottomInset` alone —
        // the same constant `collapsedPeek` rests on — is what puts the
        // button on that same low baseline. `sheetHeight - sheetOffset` is
        // the only thing that then lifts it: zero at `.collapsed`, so it sits
        // right there next to the peek pill, and it grows exactly as fast as
        // the sheet rises, so the gap above the sheet's own top edge never
        // opens past that same `peekBottomInset`.
        .padding(.bottom, max(0, sheetHeight - sheetOffset) + peekBottomInset)
        .opacity(isHidden ? 0 : 1)
        .allowsHitTesting(!isHidden)
        .animation(.hooprSnap, value: isHidden)
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
        ZStack(alignment: .top) {
            // A standalone layer, not a `.background` on the conditional
            // content below: the three panes are swapped by a transition, and
            // backing whichever one is currently in gives the surface that
            // transition too — the corner radius and shadow crossfading along
            // with the rows. A fixed sibling stays put while the contents
            // change over it.
            //
            // It stops at this tab's bottom edge, where the tab bar's
            // reserved space begins. Below that the band belongs to the
            // tab's own background (see `body`), which is the same
            // `hooprSurface`, so the two read as one surface.
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .fill(Color.hooprSurface)
                .shadow(color: Color.hooprShadow(opacity: 0.08), radius: 12, x: 0, y: -4)
                .frame(height: sheetHeight)

            // Search outranks both: focusing the field is an explicit request
            // for it, and it would be strange for a detail card opened earlier
            // to keep the surface while the user is typing.
            Group {
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
            // The container's own bottom edge already sits flush with the
            // tab bar — the ZStack is laid out net of the bar's reserved
            // space, the same way it is for every other tab — so the content
            // needs no extra padding to reach it. `tabBarInset` is for the
            // keyboard, not this.
            .frame(height: sheetHeight, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .offset(y: sheetOffset)
        // As the sheet nears `.collapsed` it slides down far enough that its
        // own top edge — the handle, the header — ends up sitting behind the
        // tab bar rather than above it. The tab bar floats on glass, so
        // without this the sliding content stayed visible through it right as
        // `collapsedPeek` faded in over the same span. Fading the two
        // opposite one another (`peekOpacity` here inverted) keeps exactly one
        // of them on screen at a time.
        .opacity(1 - peekOpacity)
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
        .hooprGlass(in: .capsule)
        .contentShape(Capsule())
        .gesture(sheetDragGesture(fromHandle: true))
        // The container's bottom edge already sits flush with the tab bar —
        // see `sheet` — so this only needs its own small resting gap, the
        // same `peekBottomInset` the sheet's content keeps above the fold.
        .padding(.bottom, peekBottomInset)
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
                emptyStateContent
            } else if viewModel.selectedTab == .now {
                activeList
            } else {
                nearbyList
            }

            if viewModel.isCurrentListEmpty,
               viewModel.selectedTab == .now,
               viewModel.datasetError == nil,
               viewModel.nearestCourtForNewRun != nil {
                Spacer()
                    .frame(height: 60)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.isCurrentListEmpty,
               viewModel.selectedTab == .now,
               viewModel.datasetError == nil,
               let court = viewModel.nearestCourtForNewRun {
                VStack(spacing: 0) {
                    Divider()
                        .overlay(Color.hooprBorder)

                    Button("Start a run") {
                        startingRunAt = court
                    }
                    .buttonStyle(.hooprFilled(.large))
                    .padding(.horizontal, Spacing.pageMargin)
                    .padding(.vertical, 12)
                }
                .background(Color.hooprSurface)
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
                .hooprType(.label)
                .foregroundStyle(Color.hooprSecondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.pageMargin)
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
                CourtName(name: court.displayName)
                    .hooprFont(16, weight: .semibold)
                    .foregroundStyle(Color.hooprPrimaryText)

                Text("\(court.city) · \(viewModel.distanceText(for: court)) away")
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, Spacing.pageMargin)
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

            attributionFooter
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

            attributionFooter
        }
    }

    /// The court data's licence notice, at the foot of every court list.
    ///
    /// **An outstanding licence obligation until 2026-09-22.** The courts are
    /// derived from OpenStreetMap under the ODbL, which requires the
    /// attribution to be shown; the dataset carried the notice and nothing
    /// displayed it (`gaps/ASSETS_AND_DATA.md`). The text is the dataset's own
    /// — `CourtService.attribution`, not a copy — and it links to
    /// OpenStreetMap's copyright page, which is what their attribution
    /// guidance asks of a notice.
    ///
    /// At the end of the list rather than pinned: it must be findable, not
    /// take the room a court row would at the `.medium` detent.
    @ViewBuilder
    private var attributionFooter: some View {
        if let attribution = viewModel.dataAttribution {
            Link(destination: viewModel.dataAttributionURL) {
                Text(attribution)
                    .hooprType(.caption)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.pageMargin)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.sm)
            .accessibilityHint("Opens the OpenStreetMap copyright page")
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
            .padding(.bottom, peekBottomInset)
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
                    withAnimation(.hooprSpring) {
                        viewModel.selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 7) {
                        // Three tabs divide one row evenly. The 17pt cap is
                        // what keeps "Nearby" inside a third of the width at
                        // every text size — it used to shrink to fit as well
                        // (`minimumScaleFactor(0.7)`), which the cap had
                        // already made dead code; the app no longer shrinks
                        // text anywhere.
                        Text(tab.title)
                            .hooprFont(13, weight: isSelected ? .bold : .medium, maximumSize: 17)
                            .foregroundStyle(isSelected ? Color.hooprPrimaryText : Color.hooprSecondaryText)
                            .lineLimit(1)

                        Rectangle()
                            .fill(isSelected ? Color.hooprBrandAccent : Color.hooprBorder)
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
    /// The `.now` segment shows the icon and title; the button is pinned to
    /// the bottom via `safeAreaInset` so it stays accessible even when the
    /// sheet is collapsed. Follows `HomeTab`'s `noRunCard`, which answers the
    /// same problem.
    private var emptyStateContent: some View {
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

            Spacer()

            // The pins above are still the court data even when this segment
            // lists none of it, so the notice doesn't leave with the rows.
            attributionFooter
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
    /// Two fixed pieces and a scroll, and the split is load-bearing at the
    /// `.medium` detent: the grab handle, a **scrolling** body — the court's
    /// name and details, its runs, its badges — and a **pinned** action row.
    /// Letting the whole card scroll would put "Start Run" below the fold —
    /// you'd have to scroll to find the primary action on a screen that exists
    /// to start runs. (The name used to be a fixed third band; see the note in
    /// the body for why it scrolls now.)
    ///
    /// **The card sets its own `.medium` height** (2026-09-23). The list's
    /// medium is a third of the container, ~215pt since the map stopped above
    /// the tab bar, which left this body ~112pt: the name and distance, then
    /// half a run. The card now measures its lead — header plus first run —
    /// and the sheet rests tall enough for it (`cardFittedHeight`,
    /// `SheetGeometry.fittedMediumHeight`). Further runs and the badges still
    /// scroll.
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

            // Scrolls, so a court with three runs is reachable by dragging the
            // sheet up rather than by the card growing past its detent.
            //
            // **The header scrolls too, since 2026-09-22.** It used to be a
            // fixed band above this, and that only held while the name was
            // capped at two lines — which is what truncated it to "East En…"
            // at `.accessibility3`. Once the name wraps in full, a fixed header
            // at that size is taller than the `.medium` sheet, and it pushed
            // the pinned action row below the fold: the one thing this layout
            // exists to prevent. The action row is what's load-bearing, so the
            // header gives way instead — at the top of the scroll it reads
            // exactly as it did, and it only moves if you scroll the runs.
            sheetScroll {
                VStack(alignment: .leading, spacing: 10) {
                    // The lead — what the card must show whole at `.medium` —
                    // measured, so the sheet can rest tall enough for it.
                    VStack(alignment: .leading, spacing: 10) {
                        cardHeader(court: court)
                            .padding(.bottom, 4)

                        if let first = games.first {
                            runRow(first)
                        } else {
                            noRunsToday
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        guard abs(height - cardLeadHeight) > 0.5 else { return }
                        withAnimation(.hooprSpring) {
                            cardLeadHeight = height
                        }
                    }

                    ForEach(games.dropFirst()) { game in
                        runRow(game)
                    }

                    CourtBadges(court: court)
                        .padding(.top, 2)
                }
                .padding(.horizontal, Spacing.pageMargin)
                .padding(.top, Self.cardScrollTopInset)
                // `sheetScroll`'s stack centres its children, which is right
                // for full-width rows and wrong for this card — without it the
                // copy floats mid-sheet while the header above it is flush left.
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            cardActions(court: court, hasRuns: !games.isEmpty)
                .padding(.horizontal, Spacing.pageMargin)
                .padding(.top, 10)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The court's name, where it is, and the two controls that belong to it.
    ///
    /// **The name gives way, and it gives way in the right order.** It shared
    /// one `HStack` with the star and close buttons, both of which scaled with
    /// the reader's text size — so at `.accessibility3` they took the width the
    /// name needed and the card showed "East En…" and "Durham · 0.…". Now the
    /// buttons sit in fixed 44pt
    /// targets with capped glyphs, and a name that still doesn't fit sheds its
    /// least informative parts before any letters go: "East End Park" reads
    /// "East End" at `.accessibility3`, not "East En…". (It wrapped to several
    /// lines for one build; the user preferred one compact row, with the full
    /// name left to the Runs tab.)
    ///
    /// The name is set in the `title` tier — up from 17pt — because it is what
    /// the card is about. Not `display`: every point this header takes is a
    /// point the sheet has to rise at `.medium` to show the first run whole
    /// (`cardFittedHeight`), and the runs are what the card leads with.
    private func cardHeader(court: Court) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // One row, always: the name gives way rather than the header
            // growing. A name that doesn't fit beside the controls sheds
            // "Park", then its court number, then is cut (`CourtName`) — the
            // full name is what the Runs tab shows.
            HStack(alignment: .center, spacing: Spacing.sm) {
                CourtTitle(name: court.displayName, isHeader: true, fit: .fitsOneLine)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                cardControls(court: court)
            }

            courtMeta(court)
        }
    }

    /// City and distance, each with its icon, on a line that wraps rather than
    /// truncates — the same treatment as Home's band, so a distance reads the
    /// same wherever it appears.
    private func courtMeta(_ court: Court) -> some View {
        FlowLayout(spacing: Spacing.lg, lineSpacing: Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "building.2.fill")
                    .hooprType(.caption)
                Text(court.city)
                    .hooprType(.body)
            }
            .foregroundStyle(Color.hooprSecondaryText)

            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                    .hooprType(.caption)
                    .foregroundStyle(Color.hooprSecondaryText)
                Text("\(Text(viewModel.distanceValueText(for: court)).fontWeight(.semibold).foregroundStyle(Color.hooprPrimaryText)) \(Distance.unit) away")
                    .hooprType(.body)
                    .foregroundStyle(Color.hooprSecondaryText)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(viewModel.distanceText(for: court)) away")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Favourite and close. Fixed 44pt targets with capped glyphs: these are
    /// controls inside a frame that can't grow, which is the one case
    /// `hooprFont`'s `maximumSize` exists for — and letting them grow is what
    /// took the name's width.
    private func cardControls(court: Court) -> some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.hooprSnap) {
                    viewModel.toggleFavorite(court)
                }
            } label: {
                Image(systemName: viewModel.isFavorite(court) ? "star.fill" : "star")
                    .hooprFont(19, maximumSize: 24)
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(
                        viewModel.isFavorite(court) ? Color.hooprBrandAccent : Color.hooprSecondaryText
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isFavorite(court) ? "Remove favorite" : "Add favorite")

            Button {
                dismissDetail()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .hooprFont(24, maximumSize: 30)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
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
    ///
    /// **Read in the same order as a run on the Runs board** (UI revamp Phase
    /// 2b): the time first, as the row's rank, then whether there is room as a
    /// number, then your standing — HOSTING / WAITLIST / FULL, in `GameCard`'s
    /// priority — and the same waitlist note. It stays a compact row rather
    /// than a `GameCard` because every run here is at *this* court: the card's
    /// court name and distance would repeat the header right above it.
    ///
    /// Two layouts: the action beside the facts, or — when the time, badge and
    /// button can't share a line — the action below at full width, so nothing
    /// has to wrap mid-word to make room for a button.
    private func runRow(_ game: Game) -> some View {
        let action = viewModel.action(for: game)
        let isPending = viewModel.pendingGameId == game.id
        let isBlocked = viewModel.pendingGameId != nil && !isPending

        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Spacing.md) {
                // Sized before the spacer, not alongside it. Without the
                // priority the HStack split the leftover width evenly between
                // the facts and the spacer, handing the time and its badge
                // ~100pt: "HOSTIN / G" on the device (2026-09-23), and a row
                // tall enough to fall below the `.medium` sheet's fold.
                runFacts(game)
                    .layoutPriority(1)
                Spacer(minLength: Spacing.sm)
                runAction(action, on: game, isPending: isPending, isBlocked: isBlocked, fullWidth: false)
            }

            VStack(alignment: .leading, spacing: Spacing.md) {
                runFacts(game)
                runAction(action, on: game, isPending: isPending, isBlocked: isBlocked, fullWidth: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardChrome(cornerRadius: 12)
    }

    private func runFacts(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(game.timeText)
                    .hooprType(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(Color.hooprPrimaryText)

                if let status = runStatus(for: game) {
                    // One word, one line, never broken (`HooprBadge`). If it
                    // can't fit beside the time and the button,
                    // `ViewThatFits` in `runRow` moves the button below instead.
                    HooprBadge(status, on: .surface)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .hooprType(.caption)
                    .foregroundStyle(Color.hooprSecondaryText)

                if game.isFull {
                    Text("Full")
                        .hooprType(.body)
                        .foregroundStyle(Color.hooprSecondaryText)
                } else {
                    Text("\(Text("\(game.openSlots)").fontWeight(.semibold).foregroundStyle(Color.hooprPrimaryText)) \(game.openSlots == 1 ? "spot left" : "spots left")")
                        .hooprType(.body)
                        .foregroundStyle(Color.hooprSecondaryText)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(game.spotsText)

            // Same note, same words as `GameCard`: a waitlist place never
            // promotes (`gaps/GAMES.md`), and the map is the other surface a
            // player can join from.
            if viewModel.isWaitlisted(game) {
                Text("Waitlist spots don't move up yet — ask the host if someone drops.")
                    .hooprType(.caption)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    @ViewBuilder
    private func runAction(
        _ action: LocalRunsViewModel.Action,
        on game: Game,
        isPending: Bool,
        isBlocked: Bool,
        fullWidth: Bool
    ) -> some View {
        if action != .none {
            Button {
                if action == .cancel {
                    runPendingCancel = game
                } else {
                    Task { await viewModel.perform(action, on: game) }
                }
            } label: {
                if isPending {
                    ProgressView()
                } else {
                    // One line: `ViewThatFits` in `runRow` moves the button
                    // below the facts rather than let its label wrap.
                    Text(action.title)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.hooprFilled(
                .compact,
                role: action.isDestructive ? .destructive : .primary,
                fillsWidth: fullWidth
            ))
            .disabled(isPending || isBlocked)
            .opacity(isBlocked ? 0.5 : 1)
        }
    }

    /// `RunStatus`'s ladder — the one `GameCard` and Home draw.
    private func runStatus(for game: Game) -> RunStatus? {
        RunStatus.of(
            isHost: viewModel.isHost(game),
            isWaitlisted: viewModel.isWaitlisted(game),
            isFull: game.isFull
        )
    }

    private var noRunsToday: some View {
        Text("No runs here today.")
            .hooprType(.body)
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
                    Text("Directions")
                }
            }
            .buttonStyle(.hooprFilled(.large, role: .secondary))

            Button {
                startingRunAt = court
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text(hasRuns ? "Add a run" : "Start Run")
                }
            }
            .buttonStyle(.hooprFilled(.large))
        }
    }

    /// Hands the court to Maps for routing. The app knows where its courts are
    /// but nothing about how to get to one, and every phone already has a
    /// router on it.
    private func openDirections(to court: Court) {
        let coordinate = CLLocationCoordinate2D(
            latitude: court.latitude,
            longitude: court.longitude
        )
        // `MKAddress` is iOS 26; the app's floor is 18. The older initialiser
        // carries no address, so pre-26 Maps resolves the pin from the
        // coordinate alone — the route is identical, the callout is terser.
        let item: MKMapItem
        if #available(iOS 26.0, *) {
            item = MKMapItem(
                location: CLLocation(latitude: court.latitude, longitude: court.longitude),
                address: court.address.isEmpty
                    ? nil
                    : MKAddress(fullAddress: court.address, shortAddress: nil)
            )
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        }
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
        withAnimation(.hooprSpring) {
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
        withAnimation(.hooprSpring) {
            // Detail reads best at the medium detent — expanded leaves a card
            // stranded in whitespace.
            let fallback: SheetDetent = sheetState.detent == .collapsed ? .collapsed : .medium
            sheetState = .detail(court: court, returningTo: fallback)
        }
    }

    private func dismissDetail() {
        guard sheetState.selectedCourt != nil else { return }
        withAnimation(.hooprSpring) {
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
        squadService: SquadService(authService: authService),
        courtToSelect: $courtToSelect,
        onOpenProfile: {}
    )
}
