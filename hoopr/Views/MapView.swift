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
    static let clusterReuseID = "courtClusterMarker"

    private static let courtDiameter: CGFloat = 34
    /// Slightly larger than a single court, so a group reads as "more than one"
    /// before you've read the number in it.
    private static let clusterDiameter: CGFloat = 38
    private static let ringWidth: CGFloat = 3

    private let ring = UIView()
    private let disc = UIView()
    private let glyph = UIImageView()
    private let countLabel = UILabel()

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
        glyph.image = UIImage(
            systemName: "basketball.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        )
        disc.addSubview(glyph)

        countLabel.textAlignment = .center
        countLabel.textColor = UIColor(Color.hooprOnBrand)
        countLabel.font = .systemFont(ofSize: 14, weight: .bold)
        disc.addSubview(countLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CourtMarkerView is created in code, never from a nib")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        transform = .identity
    }

    /// - Parameters:
    ///   - color: The disc fill. Callers pass `CourtHeat.color(forGameCount:)`
    ///     for that court, bridged to `UIColor` — selection no longer swaps the
    ///     tint (see the type-level note on why), so the same colour is drawn
    ///     whichever branch below runs.
    ///   - isSelected: Still drives the scale-up and collision priority. A
    ///     selected pin outranking its neighbours is what stops MapKit hiding
    ///     it when markers collide; that signal is independent of colour, so
    ///     it survives the heat map without conflating "selected" with "busy".
    func configureAsCourt(color: UIColor, isSelected: Bool) {
        layOut(diameter: Self.courtDiameter)

        disc.backgroundColor = color
        glyph.frame = disc.bounds
        glyph.isHidden = false
        countLabel.isHidden = true

        displayPriority = isSelected ? .required : .defaultHigh
        zPriority = isSelected ? .max : .defaultUnselected
        transform = isSelected
            ? CGAffineTransform(scaleX: 1.25, y: 1.25)
            : .identity
    }

    /// - Parameters:
    ///   - memberCount: How many courts this cluster folds together — what the
    ///     disc's number actually reads.
    ///   - color: The disc fill, from `CourtHeat.color(forGameCount:)` over the
    ///     **sum** of games across every court in the cluster — see
    ///     `MapView.heatColor(forCluster:)`. Deliberately not the member count:
    ///     a bundle of five quiet courts should read as cool, not busy, and a
    ///     bundle of two courts hosting six games between them should read hot
    ///     even though the number on the disc just says "2".
    func configureAsCluster(memberCount: Int, color: UIColor) {
        layOut(diameter: Self.clusterDiameter)

        disc.backgroundColor = color
        countLabel.frame = disc.bounds
        countLabel.text = "\(memberCount)"
        countLabel.isHidden = false
        glyph.isHidden = true

        displayPriority = .required
        zPriority = .max
        transform = .identity
    }

    private func layOut(diameter: CGFloat) {
        bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        ring.frame = bounds
        ring.layer.cornerRadius = diameter / 2

        disc.frame = ring.bounds.insetBy(dx: Self.ringWidth, dy: Self.ringWidth)
        disc.layer.cornerRadius = disc.bounds.width / 2
    }
}

struct MapView: UIViewRepresentable {
    let courts: [Court]
    let initialRegion: MKCoordinateRegion
    @Binding var recenterTrigger: RecenterTrigger?
    /// How many games are scheduled today at each court, keyed by `Court.id`.
    /// Drives a pin's fill through `CourtHeat` — see `heatColor(for:)` and
    /// `heatColor(forCluster:)`, the two places this is actually read.
    var gameCountByCourtID: [String: Int] = [:]
    /// Drawn larger, and outranking its neighbours in a collision, so the
    /// tapped court stays findable once the sheet covers part of the map.
    /// No longer changes colour — see `CourtHeat`.
    var selectedCourtID: String?
    var onMarkerTap: ((Court) -> Void)?
    var onMarkerDeselect: (() -> Void)?

    /// Bounds on how far a programmatic zoom may travel. The stepped zoom
    /// buttons that used to read these are gone — pinch has no such limit —
    /// but a cluster tap still clamps against `minDelta` so tapping the last
    /// group doesn't bottom out the map.
    fileprivate static let minDelta: Double = 0.01
    fileprivate static let maxDelta: Double = 5.0

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

    /// A cluster's heat colour: the **sum** of today's games across every
    /// court it folds together, not the member count MapKit hands back —
    /// those answer different questions, and only one of them is "how busy".
    fileprivate func heatColor(forCluster cluster: MKClusterAnnotation) -> UIColor {
        let total = cluster.memberAnnotations
            .compactMap { ($0 as? CourtAnnotation)?.court.id }
            .reduce(0) { $0 + (gameCountByCourtID[$1] ?? 0) }
        return UIColor(CourtHeat.color(forGameCount: total))
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
        mapView.register(
            CourtMarkerView.self,
            forAnnotationViewWithReuseIdentifier: CourtMarkerView.clusterReuseID
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
        for annotation in mapView.annotations {
            switch annotation {
            case let court as CourtAnnotation:
                guard let markerView = mapView.view(for: court) as? CourtMarkerView
                else { continue }
                markerView.configureAsCourt(
                    color: heatColor(for: court.court),
                    isSelected: court.court.id == selectedCourtID
                )

            case let cluster as MKClusterAnnotation:
                guard let markerView = mapView.view(for: cluster) as? CourtMarkerView
                else { continue }
                markerView.configureAsCluster(
                    memberCount: cluster.memberAnnotations.count,
                    color: heatColor(forCluster: cluster)
                )

            default:
                continue
            }
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

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            // A hundred courts across two cities pile into an unreadable mass
            // when zoomed out, so let MapKit collapse them into counted groups.
            if let cluster = annotation as? MKClusterAnnotation {
                guard let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: CourtMarkerView.clusterReuseID,
                    for: cluster
                ) as? CourtMarkerView else { return nil }

                view.annotation = cluster
                view.configureAsCluster(
                    memberCount: cluster.memberAnnotations.count,
                    color: parent.heatColor(forCluster: cluster)
                )
                return view
            }

            guard let court = annotation as? CourtAnnotation,
                  let view = mapView.dequeueReusableAnnotationView(
                      withIdentifier: CourtMarkerView.courtReuseID,
                      for: court
                  ) as? CourtMarkerView
            else { return nil }

            view.annotation = court
            view.clusteringIdentifier = CourtMarkerView.courtReuseID
            view.configureAsCourt(
                color: parent.heatColor(for: court.court),
                isSelected: court.court.id == parent.selectedCourtID
            )
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            // Tapping a group zooms in rather than leaving the user to pinch.
            if let cluster = view.annotation as? MKClusterAnnotation {
                mapView.deselectAnnotation(cluster, animated: false)
                let region = MKCoordinateRegion(
                    center: cluster.coordinate,
                    span: MKCoordinateSpan(
                        latitudeDelta: max(mapView.region.span.latitudeDelta / 2.5, MapView.minDelta),
                        longitudeDelta: max(mapView.region.span.longitudeDelta / 2.5, MapView.minDelta)
                    )
                )
                mapView.setRegion(region, animated: true)
                return
            }

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
