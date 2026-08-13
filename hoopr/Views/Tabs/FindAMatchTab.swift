import SwiftUI
import MapKit

struct FindAMatchTab: View {
    /// The bottom sheet is always in exactly one of these. `.detail` carries the
    /// state to fall back to, so dismissing a court restores whatever the sheet
    /// was showing beforehand.
    private enum SheetState: Equatable {
        case list
        case collapsed
        case detail(court: Court, returningTo: RestState)

        /// The two states the sheet rests in when no court is selected.
        enum RestState {
            case list
            case collapsed

            var sheetState: SheetState {
                self == .list ? .list : .collapsed
            }
        }

        var restState: RestState {
            switch self {
            case .list:
                return .list
            case .collapsed:
                return .collapsed
            case .detail(_, let returningTo):
                return returningTo
            }
        }

        var selectedCourt: Court? {
            if case .detail(let court, _) = self { return court }
            return nil
        }
    }

    @StateObject private var viewModel: FindAMatchViewModel
    @State private var recenterTrigger: RecenterTrigger?
    @State private var zoomTrigger: ZoomTrigger?
    @State private var absoluteZoomTrigger: AbsoluteZoomTrigger?
    @State private var zoomLevel: Double = 0.5
    @State private var isDraggingSlider = false
    @State private var sheetState: SheetState = .list

    /// Live finger travel for the sheet drag; zero whenever the sheet is settled.
    @State private var sheetDrag: CGFloat = 0
    /// How far the court list has scrolled — the sheet only takes over a drag
    /// that starts at the top.
    @State private var listScrollOffset: CGFloat = 0

    /// Height of the handle + count label that stays on screen when collapsed.
    private let headerHeight: CGFloat = 52
    /// Gap kept below the sheet's own content, and under the collapsed pill, so
    /// neither sits beneath the home indicator.
    private let peekBottomInset: CGFloat = 28
    private let collapseThreshold: CGFloat = 60
    /// Finger travel below which a handle drag counts as a tap instead.
    private let tapSlop: CGFloat = 6

    init(
        courtService: CourtService,
        locationService: LocationService,
        userProfileService: UserProfileService
    ) {
        _viewModel = StateObject(wrappedValue: FindAMatchViewModel(
            courtService: courtService,
            locationService: locationService,
            userProfileService: userProfileService
        ))
    }

    private var sheetHeight: CGFloat {
        UIScreen.main.bounds.height / 3
    }

    /// Collapsing drops the sheet clear off the bottom — the floating pill, not
    /// a sliver of the sheet, is what stays behind.
    private var collapsedOffset: CGFloat {
        sheetHeight
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            MapView(
                courts: viewModel.courts,
                initialRegion: viewModel.initialRegion,
                recenterTrigger: $recenterTrigger,
                zoomTrigger: $zoomTrigger,
                absoluteZoomTrigger: $absoluteZoomTrigger,
                onMarkerTap: { court in
                    select(court)
                },
                onMarkerDeselect: {
                    dismissDetail()
                },
                onZoomLevelChange: { level in
                    if !isDraggingSlider {
                        zoomLevel = level
                    }
                }
            )

            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        VStack(spacing: 0) {
                            Button {
                                zoomTrigger = ZoomTrigger(direction: .zoomIn)
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.black)
                                    .frame(width: 44, height: 38)
                            }

                            Divider().frame(width: 28)

                            Slider(
                                value: $zoomLevel,
                                in: 0...1,
                                onEditingChanged: { editing in
                                    isDraggingSlider = editing
                                }
                            )
                            .tint(Color.hooprOrange)
                            .frame(width: 90)
                            .rotationEffect(.degrees(-90))
                            .frame(width: 44, height: 90)
                            .clipped()

                            Divider().frame(width: 28)

                            Button {
                                zoomTrigger = ZoomTrigger(direction: .zoomOut)
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.black)
                                    .frame(width: 44, height: 38)
                            }
                        }
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 2)

                        Button {
                            recenterMap()
                        } label: {
                            Image(systemName: "location.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.hooprOrange)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 2)
                        }
                    }
                    .padding(.trailing, 14)
                    .padding(.top, 14)
                }
                Spacer()
            }

            sheet

            collapsedPeek
        }
        .onAppear {
            zoomLevel = MapView.zoomLevelFromSpan(viewModel.initialRegion.span)
        }
        .onChange(of: zoomLevel) { _, newValue in
            if isDraggingSlider {
                absoluteZoomTrigger = AbsoluteZoomTrigger(level: newValue)
            }
        }
    }

    // MARK: - Sheet

    /// One continuous white surface whose contents swap between the nearby list
    /// and a selected court's detail card.
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
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
                .fill(.white)
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: -4)
        )
        .offset(y: sheetOffset)
    }

    /// All that's left once the sheet is dismissed — a compact tap target that
    /// fades in over the back half of the drag as the sheet clears the screen.
    private var collapsedPeek: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.up")
                .font(.system(size: 11, weight: .semibold))

            Text(nearbyCountLabel)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(Color.hooprSecondaryText)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.white)
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 2)
        )
        .contentShape(Capsule())
        .gesture(sheetDragGesture(fromHandle: true))
        .padding(.bottom, peekBottomInset)
        .opacity(peekOpacity)
        .allowsHitTesting(peekOpacity > 0.5)
    }

    /// Held at zero until the sheet is most of the way gone, so the pill never
    /// competes with the sheet it replaces.
    private var peekOpacity: Double {
        guard sheetState.selectedCourt == nil, collapsedOffset > 0 else { return 0 }
        let progress = min(max(sheetOffset / collapsedOffset, 0), 1)
        return Double(min(max((progress - 0.6) / 0.4, 0), 1))
    }

    private var courtList: some View {
        VStack(spacing: 0) {
            sheetHeader
                .gesture(sheetDragGesture(fromHandle: true))

            Divider().overlay(Color.hooprBorderGray)

            if viewModel.nearbyCourts.isEmpty {
                Spacer()
                Text("No courts within \(Int(viewModel.radiusMiles)) miles")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.hooprSecondaryText)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.nearbyCourts) { nearby in
                            Button {
                                select(nearby.court, recenter: true)
                            } label: {
                                CourtRow(nearbyCourt: nearby)
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .overlay(Color.hooprBorderGray)
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

    /// Drag handle plus court count — the only part left visible when collapsed.
    private var sheetHeader: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.hooprBorderGray)
                .frame(width: 36, height: 5)

            Text(nearbyCountLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.hooprSecondaryText)
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity)
        .frame(height: headerHeight, alignment: .top)
        .contentShape(Rectangle())
    }

    private var nearbyCountLabel: String {
        let count = viewModel.nearbyCourts.count
        return count == 1 ? "1 court nearby" : "\(count) courts nearby"
    }

    @ViewBuilder
    private func courtCard(court: Court) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.hooprBorderGray)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 14)

            HStack(alignment: .center) {
                Image(systemName: "basketball.fill")
                    .foregroundStyle(Color.hooprOrange)
                    .font(.system(size: 20))

                Text(court.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Button {
                    dismissDetail()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)

            if !court.address.isEmpty {
                Text(court.address)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.hooprSecondaryText)
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sheet position

    private var sheetOffset: CGFloat {
        let base: CGFloat = sheetState == .collapsed ? collapsedOffset : 0
        return rubberBanded(base + sheetDrag)
    }

    /// Keeps the sheet inside its travel range while still following the finger,
    /// so it can be neither flung off-screen nor dragged above its full height.
    private func rubberBanded(_ offset: CGFloat) -> CGFloat {
        if offset < 0 {
            return -resistance(-offset)
        }
        if offset > collapsedOffset {
            return collapsedOffset + resistance(offset - collapsedOffset)
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
                let target: SheetState.RestState

                if fromHandle, abs(value.translation.height) < tapSlop {
                    // Barely moved, so treat it as a tap on the handle: toggle,
                    // putting the sheet one touch from minimised either way.
                    target = sheetState.restState == .collapsed ? .list : .collapsed
                } else {
                    // Project the fling so a quick flick settles the same way a
                    // long drag does.
                    let projected = value.predictedEndTranslation.height
                    switch sheetState.restState {
                    case .list:
                        target = projected > collapseThreshold ? .collapsed : .list
                    case .collapsed:
                        target = projected < -collapseThreshold ? .list : .collapsed
                    }
                }

                sheetDrag = 0
                settle(to: target)
            }
    }

    private func settle(to rest: SheetState.RestState) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            sheetState = rest.sheetState
        }
    }

    // MARK: - Selection

    private func select(_ court: Court, recenter: Bool = false) {
        viewModel.select(court)
        if recenter {
            recenterTrigger = RecenterTrigger(center: court.coordinate)
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            sheetState = .detail(court: court, returningTo: sheetState.restState)
        }
    }

    private func dismissDetail() {
        guard sheetState.selectedCourt != nil else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            sheetState = sheetState.restState.sheetState
        }
    }

    private func recenterMap() {
        recenterTrigger = RecenterTrigger(center: viewModel.recenterTarget())
    }
}

#Preview {
    let authService = AuthService()
    FindAMatchTab(
        courtService: CourtService(),
        locationService: LocationService(),
        userProfileService: UserProfileService(authService: authService)
    )
}
