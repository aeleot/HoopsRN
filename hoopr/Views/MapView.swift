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
    var onMarkerTap: ((Court) -> Void)?

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
            let factor: Double = trigger.direction == .zoomIn ? 0.5 : 2.0
            let currentRegion = mapView.region
            let minDelta = 0.005
            let maxDelta = 60.0
            let newLatDelta = min(max(currentRegion.span.latitudeDelta * factor, minDelta), maxDelta)
            let newLonDelta = min(max(currentRegion.span.longitudeDelta * factor, minDelta), maxDelta)
            let region = MKCoordinateRegion(
                center: currentRegion.center,
                span: MKCoordinateSpan(latitudeDelta: newLatDelta, longitudeDelta: newLonDelta)
            )
            mapView.setRegion(region, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        var lastRecenterId: UUID?
        var lastZoomId: UUID?

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
            view.canShowCallout = true
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let ann = view.annotation as? CourtAnnotation else { return }
            parent.onMarkerTap?(ann.court)
        }
    }
}
