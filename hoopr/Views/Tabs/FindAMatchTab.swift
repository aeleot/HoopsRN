import SwiftUI
import MapKit

struct FindAMatchTab: View {
    @StateObject private var viewModel: FindAMatchViewModel
    @State private var recenterTrigger: RecenterTrigger?
    @State private var zoomTrigger: ZoomTrigger?

    init(courtService: CourtService, locationService: LocationService) {
        _viewModel = StateObject(wrappedValue: FindAMatchViewModel(
            courtService: courtService,
            locationService: locationService
        ))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            MapView(
                courts: viewModel.courts,
                initialRegion: viewModel.initialRegion,
                recenterTrigger: $recenterTrigger,
                zoomTrigger: $zoomTrigger,
                onMarkerTap: viewModel.select
            )
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 12) {
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
                    if let center = viewModel.recenterTarget() {
                        recenterTrigger = RecenterTrigger(center: center)
                    }
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
    }
}

#Preview {
    FindAMatchTab(courtService: CourtService(), locationService: LocationService())
}
