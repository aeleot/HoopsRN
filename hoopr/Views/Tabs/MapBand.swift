import SwiftUI

/// The map's fixed header. Its measured height reserves a separate map rectangle.
/// The inbox is supplied by the tab, so the band can also render in the gallery.
struct MapBand<Inbox: View>: View {
    let nearbyCount: Int
    @Binding var query: String
    var isSearchFocused: FocusState<Bool>.Binding
    let activeFilters: Set<CourtFilter>
    let onToggle: (CourtFilter) -> Void
    let onClear: () -> Void
    @ViewBuilder var inbox: () -> Inbox

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Near you")
                        .hooprType(.label)
                        .foregroundStyle(Color.hooprSecondaryText)

                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                        Text("\(nearbyCount)")
                            .hooprType(.title)
                            .monospacedDigit()
                            .foregroundStyle(Color.hooprPrimaryText)
                            .hooprNumericTransition(nearbyCount)
                        Text(nearbyCount == 1 ? "court" : "courts")
                            .hooprType(.headline)
                            .foregroundStyle(Color.hooprSecondaryText)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(nearbyCount == 1 ? "1 court nearby" : "\(nearbyCount) courts nearby")
                }
                Spacer(minLength: 0)
                inbox()
            }
            .padding(.horizontal, Spacing.pageMargin)
            .padding(.bottom, Spacing.sm)

            HooprSearchField(
                text: $query,
                placeholder: "Search courts or a city",
                isFocused: isSearchFocused,
                ground: .fill,
                fillOutline: .hooprSeparatorStrong,
                capitalization: .words,
                onClear: onClear
            )
            .padding(.horizontal, Spacing.pageMargin)

            if !isSearchFocused.wrappedValue {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(CourtFilter.allCases) { filter in
                            FilterChip(symbolName: filter.symbolName, label: filter.label,
                                       isActive: activeFilters.contains(filter)) {
                                onToggle(filter)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.pageMargin)
                }
            }
        }
        .padding(.top, InboxButton.Slot.top)
        .padding(.bottom, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                HeroWash(placement: .leading(.hooprBrandWash))
                GeometryReader { proxy in
                    Image(systemName: "mappin.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.hooprBrandWatermark)
                        .rotationEffect(.degrees(-12))
                        .frame(width: proxy.size.width * 0.55)
                        .position(x: proxy.size.width * 0.94, y: proxy.size.height * 0.36)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .clipped()
            .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hooprSeparatorStrong).frame(height: 1)
        }
    }
}
