import SwiftUI
import MapKit

struct FindAMatchTab: View {
    @StateObject private var viewModel: FindAMatchViewModel
    @State private var recenterTrigger: RecenterTrigger?
    @State private var zoomTrigger: ZoomTrigger?
    @State private var absoluteZoomTrigger: AbsoluteZoomTrigger?
    @State private var zoomLevel: Double = 0.5
    @State private var isDraggingSlider = false
    @State private var selectedCourt: Court?

    init(courtService: CourtService, locationService: LocationService) {
        _viewModel = StateObject(wrappedValue: FindAMatchViewModel(
            courtService: courtService,
            locationService: locationService
        ))
    }

    private var cardHeight: CGFloat {
        UIScreen.main.bounds.height / 3
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
                    viewModel.select(court)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        selectedCourt = court
                    }
                },
                onMarkerDeselect: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selectedCourt = nil
                    }
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

            if let court = selectedCourt {
                courtCard(court: court)
                    .frame(height: cardHeight)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
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
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selectedCourt = nil
                    }
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
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
                .fill(.white)
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: -4)
        )
    }

    private func recenterMap() {
        if let center = viewModel.recenterTarget() {
            recenterTrigger = RecenterTrigger(center: center)
        }
    }
}

#Preview {
    FindAMatchTab(courtService: CourtService(), locationService: LocationService())
}
