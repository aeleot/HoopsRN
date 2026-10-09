import CoreLocation
import MapKit
import SwiftUI

/// "Tonight nearby" when nothing is scheduled anywhere today: a quiet, live
/// map of the courts around you, and one tap to the Map tab.
///
/// It replaced a single grey sentence ("Nothing scheduled anywhere today. Be
/// the first.") that left everything under Home's band an empty black page.
/// The answer is the same, but now it shows *where* you could go.
///
/// **Every part of it is honest about there being nothing on:**
///
/// - The dots are `CourtHeat`'s tier for no runs — what the same courts show as
///   on the map you land on. Never a busy colour.
/// - The rows under the map are **ghosts**: bars where a name and a count would
///   be, never a real court beside a made-up number, which would read as a real
///   run. Their dots carry the heat ramp so the shape says "this is where busy
///   courts will be listed", and nothing on them can be read.
/// - The courts are the nearest `HomeViewModel.previewCourtLimit` to the same
///   origin every distance reads, not `hotCourts` (which ranks the whole
///   dataset by how busy, not by how near).
///
/// **One button, one VoiceOver element.** The whole card opens the map with
/// nothing selected. The map and the ghost rows are hidden from VoiceOver and
/// take no touches; the card's label and hint say what it is and what it does.
///
/// **Motion is ambient and bounded** (`Motion.Drift`, `Motion.Glow`): the map
/// wanders a few points on a 24-second loop and the dots ping on the busy
/// glow's clock, in their own colour. Under Reduce Motion it is a still frame.
struct TonightNearbyPreview: View {
    let courts: [Court]
    let origin: CLLocationCoordinate2D
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                mapArea
                callToAction
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: CardChrome.cornerRadius))
            .cardChrome()
            // The map area takes no touches, so the card's own shape is what
            // the press lands on — all of it, edge to edge.
            .contentShape(RoundedRectangle(cornerRadius: CardChrome.cornerRadius))
        }
        .buttonStyle(.hooprPress)
        .accessibilityLabel("Nothing on nearby yet")
        .accessibilityHint("Opens the map.")
    }

    // MARK: - Layout

    /// The fixed geometry of the graphic. The map does not grow with Dynamic
    /// Type — nothing on it is text — so at `.accessibility3` the card grows
    /// only by the copy beneath it, which reflows.
    enum Layout {
        /// The map, ghost rows included.
        static let mapHeight: CGFloat = 208
        /// The ghost rows' block: two rows, one hairline, a little air below.
        static let ghostRowHeight: CGFloat = 38
        static let ghostBlockHeight: CGFloat = ghostRowHeight * 2 + 1 + Spacing.xs
        /// How far above the ghost rows the scrim takes to go solid.
        static let scrimFade: CGFloat = 44
    }

    // MARK: - The map

    private var mapArea: some View {
        ZStack(alignment: .bottom) {
            DriftingMap(courts: courts, origin: origin)

            scrim

            ghostRows
                .frame(height: Layout.ghostBlockHeight, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Layout.mapHeight)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The card's own surface rising over the lower map, so the ghost rows
    /// and the copy below sit on a ground whose every pairing is asserted —
    /// map tiles are not a ground anything can be measured against.
    private var scrim: some View {
        let height = Layout.ghostBlockHeight + Layout.scrimFade
        return LinearGradient(
            stops: [
                .init(color: Color.hooprSurface.opacity(0), location: 0),
                .init(color: Color.hooprSurface, location: Layout.scrimFade / height),
                .init(color: Color.hooprSurface, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height)
    }

    // MARK: - Ghost rows

    /// The shape of `HomeTab`'s hot-court row with nothing in it: a heat dot,
    /// a name bar over a city bar, a count bar at the trailing edge.
    private struct Ghost {
        let gameCount: Int
        let nameWidth: CGFloat
        let cityWidth: CGFloat
    }

    /// A busy court over a quiet one, so the dots show the ramp has a range.
    private static let ghosts = [
        Ghost(gameCount: 3, nameWidth: 148, cityWidth: 64),
        Ghost(gameCount: 1, nameWidth: 112, cityWidth: 52),
    ]

    private var ghostRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.ghosts.enumerated()), id: \.offset) { index, ghost in
                if index > 0 {
                    Rectangle()
                        .fill(Color.hooprBorder)
                        .frame(height: 1)
                }
                ghostRow(ghost)
            }
        }
        .padding(.horizontal, Spacing.cardPadding)
    }

    private func ghostRow(_ ghost: Ghost) -> some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(CourtHeat.color(forGameCount: ghost.gameCount))
                .frame(width: 10, height: 10)
                // Faded with the bars: a picture of a row, not a row.
                .opacity(0.55)

            VStack(alignment: .leading, spacing: 5) {
                bar(width: ghost.nameWidth, height: 9)
                bar(width: ghost.cityWidth, height: 6)
            }

            Spacer(minLength: Spacing.sm)

            bar(width: 34, height: 9)
        }
        .frame(height: Layout.ghostRowHeight)
    }

    /// The loading skeletons' fill (`hooprHoverFill`), so a placeholder reads
    /// the same everywhere in the app.
    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color.hooprHoverFill)
            .frame(width: width, height: height)
    }

    // MARK: - The call to action

    /// On the card's plain surface, below the map, where primary and secondary
    /// text are pairings `ThemeContrastTests` already holds.
    ///
    /// The arrow is the band's (`HomeTab.runsArrow`): the same glyph, size and
    /// colour say "this whole thing goes somewhere" in both places.
    private var callToAction: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Nothing on nearby yet")
                    .hooprType(.headline)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Open the map to find a court and start a run.")
                    .hooprType(.body)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .hooprFont(18, weight: .semibold, maximumSize: 24)
                .foregroundStyle(Color.hooprPrimaryText)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.top, Spacing.xs)
        .padding(.bottom, Spacing.cardPadding)
    }
}

// MARK: - Framing

/// Where the preview's camera looks. Pure, so the rule is tested without a map.
nonisolated enum NearbyPreviewFraming {
    /// The tightest the frame goes, on either axis. Narrower and a single
    /// court in the next block fills the card with one street.
    static let minimumSpanMeters: CLLocationDistance = 1_500

    /// The widest. Outside the dataset's six cities the nearest courts can be
    /// a state away, and a frame zoomed out to the coastline says nothing
    /// about "nearby" — so those courts fall outside the frame instead.
    static let maximumSpanMeters: CLLocationDistance = 30_000

    /// Room past the farthest court, so its dot never sits on the edge.
    static let padding = 1.4

    /// Centred on `origin`, wide and tall enough to hold every court in
    /// `courts` — within the two bounds above.
    static func region(
        around origin: CLLocationCoordinate2D,
        framing courts: [Court]
    ) -> MKCoordinateRegion {
        var farthestNorthSouth: CLLocationDistance = 0
        var farthestEastWest: CLLocationDistance = 0

        for court in courts {
            farthestNorthSouth = max(
                farthestNorthSouth,
                Distance.between(origin, CLLocationCoordinate2D(latitude: court.latitude, longitude: origin.longitude))
            )
            farthestEastWest = max(
                farthestEastWest,
                Distance.between(origin, CLLocationCoordinate2D(latitude: origin.latitude, longitude: court.longitude))
            )
        }

        return MKCoordinateRegion(
            center: origin,
            latitudinalMeters: span(holding: farthestNorthSouth),
            longitudinalMeters: span(holding: farthestEastWest)
        )
    }

    /// Both sides of the origin, padded, then clamped.
    static func span(holding farthest: CLLocationDistance) -> CLLocationDistance {
        min(max(farthest * 2 * padding, minimumSpanMeters), maximumSpanMeters)
    }
}

// MARK: - The drifting map

/// The map, drawn `Motion.Drift.overscan` larger than its frame on every side
/// and slid along the drift's loop. The clip is the card's.
private struct DriftingMap: View {
    let courts: [Court]
    let origin: CLLocationCoordinate2D

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            PreviewMap(courts: courts, origin: origin)
                // Equatable, so a tick of the drift re-evaluates the offset
                // and not the map: a new camera position sixty times a second
                // is exactly the work the offset exists to avoid.
                .equatable()
                .padding(-Motion.Drift.overscan)
                .offset(Motion.Drift.offset(at: context.date, reduceMotion: reduceMotion))
        }
    }
}

/// The map itself: the nearest courts, you, nothing else.
///
/// Muted, flat and without points of interest — the main map's basemap
/// (`MAP_LAYER.md` § Basemap suppression), so the two read as one place.
/// `interactionModes: []` and no hit testing: it is a picture of the map, and
/// the card it sits in is the button.
///
/// **The bottom safe area is the ghost rows' block.** MapKit frames its camera
/// and places its logo and legal link inside the safe area, so this keeps both
/// above the scrim instead of behind it, and centres the courts in the part of
/// the map you can see.
private struct PreviewMap: View, Equatable {
    let courts: [Court]
    let origin: CLLocationCoordinate2D

    nonisolated static func == (lhs: PreviewMap, rhs: PreviewMap) -> Bool {
        lhs.courts == rhs.courts
            && lhs.origin.latitude == rhs.origin.latitude
            && lhs.origin.longitude == rhs.origin.longitude
    }

    var body: some View {
        Map(
            position: .constant(.region(NearbyPreviewFraming.region(around: origin, framing: courts))),
            interactionModes: []
        ) {
            ForEach(courts) { court in
                Annotation("", coordinate: court.coordinate, anchor: .center) {
                    PreviewCourtDot()
                }
                .annotationTitles(.hidden)
            }

            Annotation("", coordinate: origin, anchor: .center) {
                YouAreHereMarker()
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .safeAreaPadding(.horizontal, Motion.Drift.overscan)
        .safeAreaPadding(.top, Motion.Drift.overscan)
        .safeAreaPadding(.bottom, Motion.Drift.overscan + TonightNearbyPreview.Layout.ghostBlockHeight)
    }
}

/// A court with nothing on: `CourtHeat`'s tier for no runs, pinging on the
/// busy glow's clock.
///
/// **Not `CourtGlowHalo`.** That halo means "busy" — it is reserved for courts
/// at `CourtHeat.glowsFrom` runs — so these ping in their own quiet colour,
/// at a little over half the glow's opacity. Under Reduce Motion the ping
/// holds at the glow's resting frame.
private struct PreviewCourtDot: View {
    /// The ping's opacity relative to the busy glow's.
    private static let pingOpacity = 0.6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            TimelineView(.animation(paused: reduceMotion)) { context in
                let frame = Motion.Glow.frame(
                    at: Motion.Glow.phase(at: context.date),
                    reduceMotion: reduceMotion
                )

                Circle()
                    .fill(CourtHeat.color(forGameCount: 0))
                    .frame(width: 10, height: 10)
                    .scaleEffect(frame.scale)
                    .opacity(frame.opacity * Self.pingOpacity)
            }

            Circle()
                .fill(CourtHeat.color(forGameCount: 0))
                .frame(width: 10, height: 10)
                // Lifts the dot off whatever street it lands on.
                .overlay(Circle().stroke(Color.hooprSurface, lineWidth: 1.5))
        }
        // Room for the ping at its widest, so MapKit never clips it.
        .frame(width: 10 * Motion.Glow.peakScale, height: 10 * Motion.Glow.peakScale)
    }
}

/// The origin every distance is measured from — the device, or Durham when
/// there is no fix. A puck in the text colours rather than the system's blue
/// location dot, which would claim a fix the fallback doesn't have.
private struct YouAreHereMarker: View {
    var body: some View {
        Circle()
            .fill(Color.hooprPrimaryText)
            .frame(width: 10, height: 10)
            .padding(3)
            .background(Circle().fill(Color.hooprSurface))
            .shadow(color: Color.hooprShadow(opacity: 0.25), radius: 2, x: 0, y: 1)
    }
}

#Preview {
    let origin = LocationService.defaultLocation
    let courts = (0..<5).map { index in
        Court(
            id: "c\(index)",
            name: "Court \(index)",
            latitude: origin.latitude + Double(index - 2) * 0.004,
            longitude: origin.longitude + Double(index % 3 - 1) * 0.006,
            address: "",
            city: "Durham",
            hoops: 2,
            surface: nil,
            isLit: nil,
            isCovered: nil,
            access: .public,
            osmType: nil,
            osmId: nil
        )
    }

    TonightNearbyPreview(courts: courts, origin: origin) {}
        .padding(Spacing.pageMargin)
        .background(Color.hooprBackground)
}
