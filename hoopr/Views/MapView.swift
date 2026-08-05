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
    var onMarkerTap: ((Court) -> Void)?
    var onMarkerDeselect: (() -> Void)?
    var onZoomLevelChange: ((Double) -> Void)?

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
        mapView.setRegion(initialRegion, animated: false)
        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: "court"
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
            guard annotation is CourtAnnotation else { return nil }

            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: "court",
                for: annotation
            ) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(
                annotation: annotation,
                reuseIdentifier: "court"
            )
            view.annotation = annotation
            view.markerTintColor = UIColor(red: 1.0, green: 0.494, blue: 0, alpha: 1.0)
            view.glyphImage = UIImage(systemName: "basketball.fill")
            view.canShowCallout = false
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
