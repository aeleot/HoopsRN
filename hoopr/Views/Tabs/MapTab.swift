import SwiftUI
import MapKit

struct MapTab: View {
    /// How far up the sheet is resting. `medium` is the default: enough list to
    /// be useful, enough map to stay oriented.
    private enum Detent {
        case collapsed
        case medium
        case expanded
    }

    /// The sheet is always in exactly one of these. `.detail` carries the
    /// detent to fall back to, so dismissing a court restores whatever the
    /// sheet was showing beforehand.
    private enum SheetState: Equatable {
        case rest(Detent)
        case detail(court: Court, returningTo: Detent)

        var detent: Detent {
            switch self {
            case .rest(let detent):          return detent
            case .detail(_, let returningTo): return returningTo
            }
        }

        /// Where the sheet actually renders right now. A detail card always
        /// shows at medium, regardless of what it'll restore to on dismiss —
        /// otherwise a court tapped while the list sits collapsed inherits
        /// that offset and renders entirely off-screen.
        var displayDetent: Detent {
            switch self {
            case .rest(let detent): return detent
            case .detail:            return .medium
            }
        }

        var selectedCourt: Court? {
            if case .detail(let court, _) = self { return court }
            return nil
        }
    }

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

    /// The tab's own height, fed by `onGeometryChange`. The detents are
    /// fractions of it. Seeded with a typical phone height so the first frame
    /// renders a sensibly sized sheet before geometry lands; this also avoids
    /// `UIScreen.main`, which is deprecated in iOS 26.
    @State private var containerHeight: CGFloat = 852

    /// How far down the map's floating chrome has to start to clear the app's
    /// header, which now hovers over the map rather than sitting above it.
    @Environment(\.floatingHeaderHeight) private var floatingHeaderHeight

    /// Gap kept below the sheet's own content, and under the collapsed pill, so
    /// neither sits beneath the home indicator.
    private let peekBottomInset: CGFloat = 28
    private let detentThreshold: CGFloat = 60
    /// Finger travel below which a handle drag counts as a tap instead.
    private let tapSlop: CGFloat = 6

    private let gameService: GameService

    init(
        courtService: CourtService,
        locationService: LocationService,
        userProfileService: UserProfileService,
        gameService: GameService,
        recentCourtsStore: RecentCourtsStore
    ) {
        self.gameService = gameService
        _viewModel = StateObject(wrappedValue: FindAMatchViewModel(
            courtService: courtService,
            locationService: locationService,
            userProfileService: userProfileService,
            recentCourtsStore: recentCourtsStore
        ))
    }

    // MARK: - Detent geometry

    private var mediumHeight: CGFloat { containerHeight / 3 }
    private var expandedHeight: CGFloat { containerHeight * 0.78 }

    private func baseHeight(for detent: Detent) -> CGFloat {
        switch detent {
        case .collapsed, .medium: return mediumHeight
        case .expanded:           return expandedHeight
        }
    }

    /// The sheet grows and shrinks between medium and expanded as you drag, so
    /// its top edge tracks your finger instead of the whole panel sliding.
    private var sheetHeight: CGFloat {
        let base = baseHeight(for: sheetState.displayDetent)
        return min(max(base - sheetDrag, mediumHeight), expandedHeight)
    }

    /// Only non-zero heading to or from `.collapsed`, where the sheet leaves
    /// the screen entirely rather than shrinking below its medium height.
    private var sheetOffset: CGFloat {
        let detent = sheetState.displayDetent
        let base: CGFloat = detent == .collapsed ? mediumHeight : 0
        let travel: CGFloat = detent == .collapsed
            ? sheetDrag
            : max(0, sheetDrag - (baseHeight(for: detent) - mediumHeight))
        return rubberBanded(base + travel)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            MapView(
                courts: viewModel.courts,
                initialRegion: viewModel.initialRegion,
                recenterTrigger: $recenterTrigger,
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

            sheet

            collapsedPeek
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            if height > 0 { containerHeight = height }
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

    /// Filter chips and the recenter button share one row below the header,
    /// floating over the map on glass.
    ///
    /// The trailing `Spacer` is load-bearing: it holds the stack at full
    /// height so the row stays pinned to the top of a `ZStack` that aligns
    /// its children to the bottom.
    private var mapOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                filterChips

                recenterButton
                    .padding(.trailing, 14)
            }

            Spacer()
        }
        // Clear the header hovering above, then the usual gap beneath it.
        .padding(.top, floatingHeaderHeight + 10)
        // Keep the chrome clear of the sheet, whatever height it's at.
        .padding(.bottom, max(0, sheetHeight - sheetOffset))
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CourtFilter.allCases) { filter in
                    let isActive = viewModel.isActive(filter)

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.toggle(filter)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: filter.symbolName)
                                .hooprFont(11, weight: .semibold)
                            Text(filter.label)
                                .hooprFont(13, weight: .semibold)
                        }
                        .foregroundStyle(isActive ? Color.hooprOnBrand : Color.hooprPrimaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        // Selection is carried by tinting the glass rather than
                        // swapping to an opaque fill, so an active chip is the
                        // same object lit up rather than a different one.
                        .glassEffect(
                            isActive
                                ? .regular.tint(Color.hooprOrange).interactive()
                                : .regular.interactive(),
                            in: .capsule
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        // Clipped at the frame, unlike before: the chips now share their row
        // with the recenter button, so overflow has to stop at its edge
        // instead of sliding underneath it.
    }

    /// The only map control left.
    ///
    /// There used to be a `+`/`−` pair with a vertical slider between them. It
    /// occupied a 44×180pt column of the map to duplicate a pinch every user
    /// already knows, and it was the single most dated thing on the screen —
    /// so the whole stack is gone, along with the absolute/stepped zoom
    /// triggers and the log-scale span conversion that fed it.
    private var recenterButton: some View {
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
            if let court = sheetState.selectedCourt {
                courtCard(court: court)
                    .transition(.opacity)
            } else {
                courtList
                    .transition(.opacity)
            }
        }
        .frame(height: sheetHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .fill(Color.hooprSurface)
                .shadow(color: Color.hooprShadow(opacity: 0.08), radius: 12, x: 0, y: -4)
        )
        .offset(y: sheetOffset)
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

            if viewModel.listedCourts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
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

                            Divider()
                                .overlay(Color.hooprBorder)
                                .padding(.leading, 20)
                        }
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
        }
    }

    /// Nearby / Favorites / Recent. Switching only changes which courts the
    /// sheet lists — the map and its filters are unaffected.
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

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()

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
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }

    /// Drag handle plus court count — the only part left visible when collapsed.
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

    /// The selected court.
    ///
    /// This used to be a name, an address and one button, which left roughly
    /// half the sheet empty — and meant tapping a court to learn more about it
    /// showed you *less* than the row you tapped it from. It now carries the
    /// same distance and amenity badges the list row does, plus a route out to
    /// Maps, so the card is worth the height it was already taking.
    @ViewBuilder
    private func courtCard(court: Court) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.hooprBorder)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 14)

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
            .padding(.horizontal, 20)

            CourtBadges(court: court)
                .padding(.horizontal, 20)
                .padding(.top, 12)

            // No address row. In this dataset `address` is the city and state —
            // "Durham, NC" — which the metadata line above already says. It's
            // still handed to Maps by `openDirections(to:)`, where it does work.

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
                        Text("Start Run")
                            .hooprFont(15, weight: .semibold, maximumSize: 22)
                    }
                    .foregroundStyle(Color.hooprOnBrand)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.hooprOrange)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Keeps the sheet inside its travel range while still following the finger,
    /// so it can be neither flung off-screen nor dragged above its full height.
    private func rubberBanded(_ offset: CGFloat) -> CGFloat {
        if offset < 0 {
            return -resistance(-offset)
        }
        if offset > mediumHeight {
            return mediumHeight + resistance(offset - mediumHeight)
        }
        return offset
    }

    /// Overshoot that eases towards a hard limit instead of tracking 1:1.
    private func resistance(_ overshoot: CGFloat) -> CGFloat {
        let limit: CGFloat = 40
        return limit * (1 - exp(-overshoot / limit))
    }

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
                let target: Detent

                if fromHandle, abs(value.translation.height) < tapSlop {
                    // Barely moved, so treat it as a tap on the handle: step
                    // between medium and collapsed.
                    target = sheetState.detent == .collapsed ? .medium : .collapsed
                } else {
                    // Project the fling so a quick flick settles the same way a
                    // long drag does.
                    target = nextDetent(
                        from: sheetState.detent,
                        projecting: value.predictedEndTranslation.height
                    )
                }

                sheetDrag = 0
                settle(to: target)
            }
    }

    /// One detent per gesture, so a hard fling can't skip from expanded
    /// straight off the bottom of the screen.
    private func nextDetent(from detent: Detent, projecting travel: CGFloat) -> Detent {
        switch detent {
        case .expanded:
            return travel > detentThreshold ? .medium : .expanded
        case .medium:
            if travel > detentThreshold { return .collapsed }
            if travel < -detentThreshold { return .expanded }
            return .medium
        case .collapsed:
            return travel < -detentThreshold ? .medium : .collapsed
        }
    }

    private func settle(to detent: Detent) {
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
            let fallback: Detent = sheetState.detent == .collapsed ? .collapsed : .medium
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
    let authService = AuthService()
    return MapTab(
        courtService: CourtService(),
        locationService: LocationService(),
        userProfileService: UserProfileService(authService: authService),
        gameService: GameService(authService: authService),
        recentCourtsStore: RecentCourtsStore()
    )
}
