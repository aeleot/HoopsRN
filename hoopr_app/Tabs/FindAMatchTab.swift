import SwiftUI
import MapKit

struct FindAMatchTab: View {
    @EnvironmentObject var locationManager: LocationManager
    @StateObject private var courtSearch = CourtSearchService()
    @State private var recenterTrigger: RecenterTrigger?
    @State private var zoomTrigger: ZoomTrigger?

    private static let initialRegion = MKCoordinateRegion(
        center: LocationManager.defaultLocation,
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            MapView(
                courts: courtSearch.courts,
                initialRegion: Self.initialRegion,
                recenterTrigger: $recenterTrigger,
                zoomTrigger: $zoomTrigger,
                onRegionChange: { region in
                    courtSearch.ensureCoverage(for: region)
                },
                onMarkerTap: { court in
                    print("Tapped court: \(court.name) — \(court.address)")
                }
            )
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 12) {
                if courtSearch.isSearching {
                    ProgressView()
                        .frame(width: 48, height: 48)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                }

                VStack(spacing: 0) {
                    Button {
                        zoomTrigger = ZoomTrigger(direction: .zoomIn)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 48, height: 44)
                    }

                    Divider()
                        .frame(width: 32)

                    Button {
                        zoomTrigger = ZoomTrigger(direction: .zoomOut)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 48, height: 44)
                    }
                }
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)

                Button {
                    recenterMap()
                } label: {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Color.hooprOrange)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 16)
        }
        .onAppear {
            courtSearch.ensureCoverage(for: Self.initialRegion)
        }
    }

    private func recenterMap() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestLocationPermission()
            return
        }
        let center = locationManager.userLocation ?? LocationManager.defaultLocation
        recenterTrigger = RecenterTrigger(center: center)
    }
}
