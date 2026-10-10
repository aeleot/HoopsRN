import SwiftUI

/// The map's fixed header. Its measured height reserves a separate map rectangle.
/// The inbox is supplied by the tab, so the band can also render in the gallery.
///
/// **One row: search, and the inbox in its `Slot`** (2026-10-10, the user's
/// call). It was three rows and 170pt — 23% of the tab — and the map between it
/// and a court's card was down to 283pt:
///
/// - **"Near you · 97 courts" went.** The count is the courts inside your
///   radius, a static number the sheet's header ("97 courts nearby") and the
///   peek pill already state; as the band's hero it was the least useful fact
///   on the tab. Other bands lead with a live answer — Home's next tip-off,
///   Runs' week — and this one had none to give.
/// - **The filter chips went**, three of four being refinements of the Now
///   segment (`MapViewModel.rebuild()`).
///
/// What's left is the tab's primary control, the same height in every state —
/// a court open, the list, a search — so the map's top edge never moves. A
/// header that shrank while a card was open read as something going wrong.
struct MapBand<Inbox: View>: View {
    @Binding var query: String
    var isSearchFocused: FocusState<Bool>.Binding
    let onClear: () -> Void
    @ViewBuilder var inbox: () -> Inbox

    var body: some View {
        // Top-aligned so the inbox sits exactly in its `Slot`, where every tab
        // keeps it; the field is 2pt taller and hangs below it.
        HStack(alignment: .top, spacing: Spacing.md) {
            HooprSearchField(
                text: $query,
                placeholder: "Search courts or a city",
                isFocused: isSearchFocused,
                ground: .fill,
                fillOutline: .hooprSeparatorStrong,
                capitalization: .words,
                onClear: onClear
            )

            inbox()
        }
        .padding(.horizontal, Spacing.pageMargin)
        .padding(.top, InboxButton.Slot.top)
        .padding(.bottom, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                HeroWash(placement: .leading(.hooprBrandWash))
                MapBandRadar()
            }
            .clipped()
            .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hooprSeparatorStrong).frame(height: 1)
        }
    }
}
