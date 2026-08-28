import SwiftUI
import MapKit

struct RecenterTrigger: Equatable {
    let center: CLLocationCoordinate2D
    let id: UUID

    init(center: CLLocationCoordinate2D) {
        self.center = center
        self.id = UUID()
    }

    static func == (lhs: RecenterTrigger, rhs: RecenterTrigger) -> Bool {
        lhs.id == rhs.id
    }
}

final class CourtAnnotation: NSObject, MKAnnotation {
    let court: Court
    var coordinate: CLLocationCoordinate2D { court.coordinate }

    /// Carried for VoiceOver only — `CourtMarkerView` draws no label, and
    /// callouts are off. The sheet is where a court is named on screen.
    var title: String? { court.displayName }

    init(court: Court) {
        self.court = court
        super.init()
    }
}

/// A flat circular disc, rather than MapKit's default teardrop.
///
/// Two reasons this isn't `MKMarkerAnnotationView`. The teardrop silhouette is
/// instantly recognisable as stock Apple Maps furniture, and — the bigger
/// problem — a marker view draws `annotation.title` beneath itself. With a
/// dataset where every court is named `<Place> Basketball Court`, that produced
/// labels wrapping onto three lines that covered more of the map than the roads
/// did. A plain `MKAnnotationView` subclass draws no label at all.
///
/// Colours are read from `Theme.swift` through `UIColor`, and set as UIView
/// background colours rather than layer colours, because a `UIColor` from the
/// palette's dynamic provider only re-resolves on a trait change when it's held
/// by a view. A `CALayer.backgroundColor` would freeze at whichever appearance
/// was current when it was assigned.
final class CourtMarkerView: MKAnnotationView {
    static let courtReuseID = "courtMarker"

    /// 20% down from the 34pt this was while clustering existed. With every
    /// court now drawn individually (see `MapView`'s note on why clustering
    /// was dropped), a smaller disc is what keeps a dense block of courts
    /// legible: MapKit hides a pin whose circle collides with a
    /// higher-priority neighbour's, so shrinking the circle is what lets more
    /// of them survive that test at a given zoom.
    private static let courtDiameter: CGFloat = 27
    private static let ringWidth: CGFloat = 3

    private let ring = UIView()
    private let disc = UIView()
    private let glyph = UIImageView()
    private let countLabel = UILabel()

    /// The count a pin draws, exact through 9.
    ///
    /// Deliberately *not* capped at 4 to match `CourtHeat`'s ramp. The colour
    /// ceilings there because that's where it runs out of luma to distinguish
    /// with — but the number is a different channel carrying a precise datum,
    /// and truncating it to match a limitation of the colour would discard the
    /// very information the badge exists to show. `HomeTab` caps at "4+" for
    /// the opposite and correct reason: the only other signal on that row *is*
    /// the colour dot beside it.
    static func countText(_ gameCount: Int) -> String {
        gameCount > 9 ? "9+" : "\(gameCount)"
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        // A circular pin marks its spot with its centre, unlike a teardrop
        // whose tip does — so no centre offset, and a circular collision shape
        // instead of MapKit's default rectangle.
        centerOffset = .zero
        collisionMode = .circle
        // The sheet owns detail display; a callout would be a second surface
        // saying the same thing.
        canShowCallout = false
        backgroundColor = .clear

        ring.backgroundColor = UIColor(Color.hooprSurface)
        ring.isUserInteractionEnabled = false
        // Bridged from the theme rather than `.black`, which was the one
        // literal colour left in the view layer — and the one value here that
        // wouldn't have inverted with the appearance.
        ring.layer.shadowColor = UIColor(Color.hooprShadow(opacity: 1)).cgColor
        ring.layer.shadowOpacity = 0.25
        ring.layer.shadowRadius = 3
        ring.layer.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(ring)

        disc.isUserInteractionEnabled = false
        ring.addSubview(disc)

        glyph.contentMode = .center
        glyph.tintColor = UIColor(Color.hooprOnBrand)
        // Scaled with `courtDiameter` so the glyph keeps its share of the
        // disc rather than crowding it at the smaller size.
        glyph.image = UIImage(
            systemName: "basketball.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        )
        disc.addSubview(glyph)

        // Same role the glyph uses — black, the only foreground that clears AA
        // against every stop of the heat ramp.
        countLabel.textColor = UIColor(Color.hooprOnBrand)
        countLabel.textAlignment = .center
        // Fixed size rather than Dynamic Type, the same deliberate exception
        // `PlayerAvatar`'s initial takes: this is sized as a fraction of a
        // fixed shape, and a numeral that outgrew its disc would be less
        // legible, not more. The accessibility answer for a pin is the
        // VoiceOver label set in `configureAsCourt`.
        countLabel.font = .systemFont(ofSize: 12, weight: .bold)
        countLabel.adjustsFontSizeToFitWidth = true
        countLabel.minimumScaleFactor = 0.7
        countLabel.isUserInteractionEnabled = false
        countLabel.isHidden = true
        disc.addSubview(countLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CourtMarkerView is created in code, never from a nib")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        transform = .identity
        // Both, or a recycled view carries the previous court's badge into a
        // quiet one.
        countLabel.text = nil
        countLabel.isHidden = true
        glyph.isHidden = false
    }

    /// - Parameters:
    ///   - color: The disc fill. Callers pass `CourtHeat.color(forGameCount:)`
    ///     for that court, bridged to `UIColor` — selection no longer swaps the
    ///     tint (see the type-level note on why).
    ///   - gameCount: Runs scheduled at this court today. A court with any
    ///     shows the number in place of the glyph; a quiet one keeps the glyph.
    ///     This is the pin's primary signal — the heat ramp reinforces it, but
    ///     five stops ~15 luma points apart is not something a reader can
    ///     decode into a quantity, and there is no legend to help them.
    ///   - isSelected: Still drives the scale-up and collision priority. A
    ///     selected pin outranking its neighbours is what stops MapKit hiding
    ///     it when markers collide; that signal is independent of colour, so
    ///     it survives the heat map without conflating "selected" with "busy".
    func configureAsCourt(color: UIColor, gameCount: Int, isSelected: Bool) {
        layOut()

        disc.backgroundColor = color

        // Both branches assign both views unconditionally. A recycled view that
        // only touched the branch it landed in would keep whatever the previous
        // annotation left behind.
        let isActive = gameCount > 0
        countLabel.text = isActive ? Self.countText(gameCount) : nil
        countLabel.isHidden = !isActive
        glyph.isHidden = isActive

        countLabel.frame = disc.bounds
        glyph.frame = disc.bounds

        // Priority, not size, is what makes a busy court win a collision.
        // MapKit resolves collisions during its own layout pass, *before*
        // `updateUIView`'s restyle loop mutates these views — so a pin that
        // grew when its first run was booked would keep its old footprint
        // until the next region change. `displayPriority` is re-read on the
        // next collision pass without needing a re-layout. It also keeps the
        // documented reason the disc shrank to 27pt intact.
        displayPriority = isSelected
            ? .required
            : (isActive ? .defaultHigh : .defaultLow)
        zPriority = isSelected
            ? .max
            : (isActive ? .defaultSelected : .defaultUnselected)
        transform = isSelected
            ? CGAffineTransform(scaleX: 1.25, y: 1.25)
            : .identity

        // Overrides the annotation's `title`, which alone would read out the
        // court name and say nothing about why this pin looks different.
        let name = (annotation as? CourtAnnotation)?.court.displayName ?? ""
        accessibilityLabel = isActive
            ? "\(name), \(gameCount) \(gameCount == 1 ? "run" : "runs") today"
            : name
    }

    private func layOut() {
        let diameter = Self.courtDiameter
        bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        ring.frame = bounds
        ring.layer.cornerRadius = diameter / 2

        disc.frame = ring.bounds.insetBy(dx: Self.ringWidth, dy: Self.ringWidth)
        disc.layer.cornerRadius = disc.bounds.width / 2
    }
}

/// The court map. **Every court is its own pin — there is no clustering.**
///
/// MapKit's automatic clustering was removed on 2026-08-22. It folded nearby
/// courts into a numbered disc, and that number was the problem: it counted
/// *member annotations*, so it read as a court count while sitting on a disc
/// whose colour meant games-today. Two different quantities in one badge, and
/// the count was the misleading one — "3" on a pin in a park with three
/// adjacent courts said nothing about whether anyone was playing. MapKit
/// exposes no radius/distance control over when it clusters (only the coarse
/// `clusteringIdentifier` opt-out), so there was no way to tune it into
/// something honest, and a heat map you can't read at a glance isn't worth a
/// badge that lies.
///
/// What replaces it: nothing. `CourtMarkerView` shrank 20% instead, and
/// MapKit's own collision handling (`collisionMode = .circle` plus
/// `displayPriority`) thins dense areas by *hiding* overlapping pins rather
/// than merging them — so a visible pin always means one court, and its
/// colour always means that court's games today.
struct MapView: UIViewRepresentable {
    let courts: [Court]
    let initialRegion: MKCoordinateRegion
    @Binding var recenterTrigger: RecenterTrigger?
    /// How many games are scheduled today at each court, keyed by `Court.id`.
    /// Drives a pin's fill through `CourtHeat` — see `heatColor(for:)`, the
    /// one place this is actually read.
    var gameCountByCourtID: [String: Int] = [:]
    /// Drawn larger, and outranking its neighbours in a collision, so the
    /// tapped court stays findable once the sheet covers part of the map.
    /// No longer changes colour — see `CourtHeat`.
    var selectedCourtID: String?
    var onMarkerTap: ((Court) -> Void)?
    var onMarkerDeselect: (() -> Void)?

    /// `setRegion` puts its target at the exact centre of the map view's
    /// bounds — but the map itself runs edge to edge under the floating
    /// header and behind the bottom sheet, so a target centred in the full
    /// screen actually lands below the centre of what's *visible* between
    /// them. Shifting the region's centre south moves the target north on
    /// screen without it — the same trick as
    /// `setVisibleMapRect(_:edgePadding:)`, minus the Mercator-space padding
    /// math, since the header and sheet heights aren't known here.
    ///
    /// The fraction is sized against `MapTab`'s own geometry: a ~0.14
    /// screen-height header and a sheet resting at its `.medium` detent
    /// (~⅓ of the screen) put the visible gap's centre at roughly 40% down
    /// the screen rather than 50%. 0.12 of the span covers that gap with a
    /// little headroom, without crowding the target under the header.
    private static func biasedNorth(_ region: MKCoordinateRegion) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: region.center.latitude - region.span.latitudeDelta * 0.12,
                longitude: region.center.longitude
            ),
            span: region.span
        )
    }

    /// A single court's heat colour, bridged for `CourtMarkerView`. A court
    /// absent from the dictionary has no games today, same as an explicit 0 —
    /// `CourtHeat` doesn't distinguish "counted and empty" from "never
    /// scheduled anything".
    fileprivate func heatColor(for court: Court) -> UIColor {
        UIColor(CourtHeat.color(forGameCount: gameCountByCourtID[court.id] ?? 0))
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true

        // Everything Apple's map offers that isn't "where am I and where is
        // that court". None of these carry information this app needs, and each
        // one competes with the pins for attention.
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.showsTraffic = false
        mapView.showsBuildings = false
        mapView.pitchButtonVisibility = .hidden
        mapView.selectableMapFeatures = []

        // Courts sit in parks, and Apple's default basemap renders parks in a
        // saturated green that competes with the pins on top of them. Muting
        // the basemap and dropping Apple's own POIs leaves the courts as the
        // only thing asking for attention.
        //
        // This is as far as MapKit goes: road labels, highway shields and
        // neighbourhood names have no API and stay. Getting rid of those means
        // leaving Apple's tiles — see `MAP_LAYER.md`.
        let configuration = MKStandardMapConfiguration(
            elevationStyle: .flat,
            emphasisStyle: .muted
        )
        configuration.pointOfInterestFilter = .excludingAll
        mapView.preferredConfiguration = configuration

        mapView.setRegion(Self.biasedNorth(initialRegion), animated: false)
        mapView.register(
            CourtMarkerView.self,
            forAnnotationViewWithReuseIdentifier: CourtMarkerView.courtReuseID
        )
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        let existing = mapView.annotations.compactMap { $0 as? CourtAnnotation }
        let existingIds = Set(existing.map { $0.court.id })
        let newIds = Set(courts.map { $0.id })

        let toRemove = existing.filter { !newIds.contains($0.court.id) }
        let toAdd = courts.filter { !existingIds.contains($0.id) }

        if !toRemove.isEmpty {
            mapView.removeAnnotations(toRemove)
        }
        if !toAdd.isEmpty {
            mapView.addAnnotations(toAdd.map { CourtAnnotation(court: $0) })
        }

        // `viewFor` only runs when a view is created or recycled, so selection
        // *and* heat-colour styling both have to be re-applied to the views
        // already on screen — the count backing a pin's colour can change
        // (a game gets booked) without the set of courts or the selection
        // changing at all, which is exactly the case `viewFor` never re-runs
        // for.
        for case let court as CourtAnnotation in mapView.annotations {
            guard let markerView = mapView.view(for: court) as? CourtMarkerView
            else { continue }
            markerView.configureAsCourt(
                color: heatColor(for: court.court),
                gameCount: gameCountByCourtID[court.court.id] ?? 0,
                isSelected: court.court.id == selectedCourtID
            )
        }

        if let trigger = recenterTrigger, trigger.id != context.coordinator.lastRecenterId {
            context.coordinator.lastRecenterId = trigger.id
            let region = MKCoordinateRegion(
                center: trigger.center,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
            mapView.setRegion(Self.biasedNorth(region), animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        var lastRecenterId: UUID?

        init(parent: MapView) {
            self.parent = parent
        }

        /// Never sets `clusteringIdentifier` — leaving it `nil` is what keeps
        /// MapKit from folding courts into group annotations at all. See the
        /// note on `MapView` for why that folding was dropped.
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            guard let court = annotation as? CourtAnnotation,
                  let view = mapView.dequeueReusableAnnotationView(
                      withIdentifier: CourtMarkerView.courtReuseID,
                      for: court
                  ) as? CourtMarkerView
            else { return nil }

            view.annotation = court
            view.configureAsCourt(
                color: parent.heatColor(for: court.court),
                gameCount: parent.gameCountByCourtID[court.court.id] ?? 0,
                isSelected: court.court.id == parent.selectedCourtID
            )
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let ann = view.annotation as? CourtAnnotation else { return }
            parent.onMarkerTap?(ann.court)
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self else { return }
                if mapView.selectedAnnotations.compactMap({ $0 as? CourtAnnotation }).isEmpty {
                    self.parent.onMarkerDeselect?()
                }
            }
        }
    }
}
