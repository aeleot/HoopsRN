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

enum ZoomDirection {
    case zoomIn
    case zoomOut
}

struct ZoomTrigger: Equatable {
    let direction: ZoomDirection
    let id: UUID

    init(direction: ZoomDirection) {
        self.direction = direction
        self.id = UUID()
    }

    static func == (lhs: ZoomTrigger, rhs: ZoomTrigger) -> Bool {
        lhs.id == rhs.id
    }
}

struct AbsoluteZoomTrigger: Equatable {
    let level: Double
    let id: UUID

    init(level: Double) {
        self.level = level
        self.id = UUID()
    }

    static func == (lhs: AbsoluteZoomTrigger, rhs: AbsoluteZoomTrigger) -> Bool {
        lhs.id == rhs.id
    }
}

final class CourtAnnotation: NSObject, MKAnnotation {
    let court: Court
    var coordinate: CLLocationCoordinate2D { court.coordinate }
    var title: String? { court.name }
    var subtitle: String? { court.address.isEmpty ? nil : court.address }

    init(court: Court) {
        self.court = court
        super.init()
    }
}

struct MapView: UIViewRepresentable {
    let courts: [Court]
    let initialRegion: MKCoordinateRegion
    @Binding var recenterTrigger: RecenterTrigger?
    @Binding var zoomTrigger: ZoomTrigger?
    @Binding var absoluteZoomTrigger: AbsoluteZoomTrigger?
    /// Drawn larger and in the dark brand tint so the tapped court stays
    /// findable once the sheet covers part of the map.
    var selectedCourtID: String?
    var onMarkerTap: ((Court) -> Void)?
    var onMarkerDeselect: (() -> Void)?
    var onZoomLevelChange: ((Double) -> Void)?

    private static let courtReuseID = "court"
    private static let clusterReuseID = "courtCluster"

    private static let minDelta: Double = 0.01
    private static let maxDelta: Double = 5.0

    static func zoomLevelFromSpan(_ span: MKCoordinateSpan) -> Double {
        let delta = max(min(span.latitudeDelta, maxDelta), minDelta)
        let logMin = log(minDelta)
        let logMax = log(maxDelta)
        return 1.0 - (log(delta) - logMin) / (logMax - logMin)
    }

    static func spanFromZoomLevel(_ level: Double) -> MKCoordinateSpan {
        let clamped = max(min(level, 1.0), 0.0)
        let logMin = log(minDelta)
        let logMax = log(maxDelta)
        let delta = exp(logMin + (1.0 - clamped) * (logMax - logMin))
        return MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true

        // Courts sit in parks, and Apple's default basemap renders parks in a
        // saturated green that competes with the pins on top of them. Muting
        // the basemap and dropping Apple's own POIs leaves the courts as the
        // only thing asking for attention.
        let configuration = MKStandardMapConfiguration(
            elevationStyle: .flat,
            emphasisStyle: .muted
        )
        configuration.pointOfInterestFilter = .excludingAll
        mapView.preferredConfiguration = configuration

        mapView.setRegion(initialRegion, animated: false)
        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: Self.courtReuseID
        )
        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: Self.clusterReuseID
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
        // styling has to be re-applied to the views already on screen.
        for annotation in mapView.annotations {
            guard let court = annotation as? CourtAnnotation,
                  let markerView = mapView.view(for: court) as? MKMarkerAnnotationView
            else { continue }
            Self.applyCourtStyle(
                to: markerView,
                isSelected: court.court.id == selectedCourtID
            )
        }

        if let trigger = recenterTrigger, trigger.id != context.coordinator.lastRecenterId {
            context.coordinator.lastRecenterId = trigger.id
            let region = MKCoordinateRegion(
                center: trigger.center,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
            mapView.setRegion(region, animated: true)
        }

        if let trigger = zoomTrigger, trigger.id != context.coordinator.lastZoomId {
            context.coordinator.lastZoomId = trigger.id
            let factor: Double = trigger.direction == .zoomIn ? 0.75 : 1.4
            let currentRegion = mapView.region
            let newLatDelta = min(max(currentRegion.span.latitudeDelta * factor, Self.minDelta), Self.maxDelta)
            let newLonDelta = min(max(currentRegion.span.longitudeDelta * factor, Self.minDelta), Self.maxDelta)
            let region = MKCoordinateRegion(
                center: currentRegion.center,
                span: MKCoordinateSpan(latitudeDelta: newLatDelta, longitudeDelta: newLonDelta)
            )
            mapView.setRegion(region, animated: true)
        }

        if let trigger = absoluteZoomTrigger, trigger.id != context.coordinator.lastAbsoluteZoomId {
            context.coordinator.lastAbsoluteZoomId = trigger.id
            let span = MapView.spanFromZoomLevel(trigger.level)
            let region = MKCoordinateRegion(
                center: mapView.region.center,
                span: span
            )
            mapView.setRegion(region, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// Shared by `viewFor` and `updateUIView` so a pin looks the same however
    /// its view got there.
    fileprivate static func applyCourtStyle(
        to view: MKMarkerAnnotationView,
        isSelected: Bool
    ) {
        view.markerTintColor = isSelected
            ? UIColor(Color.hooprDarkOrange)
            : UIColor(Color.hooprOrange)
        view.glyphImage = UIImage(systemName: "basketball.fill")
        // Selected pins outrank their neighbours so MapKit stops hiding them
        // when markers collide.
        view.displayPriority = isSelected ? .required : .defaultHigh
        view.zPriority = isSelected ? .max : .defaultUnselected
        view.transform = isSelected
            ? CGAffineTransform(scaleX: 1.25, y: 1.25)
            : .identity
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        var lastRecenterId: UUID?
        var lastZoomId: UUID?
        var lastAbsoluteZoomId: UUID?
        private var debounceWorkItem: DispatchWorkItem?

        init(parent: MapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            // A hundred courts across two cities pile into an unreadable mass
            // when zoomed out, so let MapKit collapse them into counted groups.
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MapView.clusterReuseID,
                    for: cluster
                ) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(
                    annotation: cluster,
                    reuseIdentifier: MapView.clusterReuseID
                )
                view.annotation = cluster
                view.markerTintColor = UIColor(Color.hooprDarkOrange)
                view.glyphText = "\(cluster.memberAnnotations.count)"
                view.glyphImage = nil
                view.canShowCallout = false
                view.displayPriority = .required
                return view
            }

            guard let court = annotation as? CourtAnnotation else { return nil }

            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: MapView.courtReuseID,
                for: court
            ) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(
                annotation: court,
                reuseIdentifier: MapView.courtReuseID
            )
            view.annotation = court
            view.canShowCallout = false
            view.clusteringIdentifier = MapView.courtReuseID
            view.glyphText = nil
            MapView.applyCourtStyle(
                to: view,
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

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            debounceWorkItem?.cancel()
            let zoomCallback = parent.onZoomLevelChange
            let zoomLevel = MapView.zoomLevelFromSpan(mapView.region.span)
            let work = DispatchWorkItem {
                zoomCallback?(zoomLevel)
            }
            debounceWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
    }
}
