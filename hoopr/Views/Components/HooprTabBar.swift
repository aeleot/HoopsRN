import SwiftUI

/// The app's three top-level destinations, defined once so the `TabView` and
/// the shelf that draws it can't disagree about the set or its order.
enum HooprTab: String, CaseIterable, Hashable {
    case home
    case map
    case runs

    var title: String {
        switch self {
        case .home: "Home"
        case .map:  "Map"
        case .runs: "Runs"
        }
    }

    /// Filled symbols, per the HIG's tab bar guidance.
    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .map:  "map.fill"
        case .runs: "calendar"
        }
    }
}

/// A full-width bottom tab shelf.
///
/// **Why this is hand-drawn rather than the system's.** iOS 26 renders
/// `TabView`'s bar as a floating Liquid Glass pill centred over the content,
/// and there is no supported way to make it span the screen: the
/// `UseFloatingTabBar` default was removed in iOS 26.4, and
/// `UIDesignRequiresCompatibility` opts the *entire app* out of Liquid Glass
/// and is scheduled for removal. A shelf that reaches both edges is a design
/// decision the platform doesn't expose, so it has to be drawn.
///
/// **What it therefore has to earn back.** The reason the shell moved to a
/// native `TabView` in the first place was the four things the system supplies
/// for free, so each is reproduced deliberately here and none of them is
/// optional:
///
/// - **44pt targets.** Each item fills a third of the width and is floored at
///   44pt tall, so the tap target is the cell, not the glyph.
/// - **Dynamic Type.** Label and glyph both scale through `.hooprFont`. They
///   carry ceilings — a tab bar that grows without bound eats the screen, and
///   Apple's own caps too — but they are ceilings on a scaling value, not fixed
///   sizes.
/// - **VoiceOver.** Every item is a button with a label and, when current, the
///   `.isSelected` trait.
/// - **Hit testing.** The shelf is an opaque fill, so unlike the old floating
///   glass header it cannot let taps through to the map underneath. That header
///   needed a `contentShape` on a clear fill to stop exactly that; this needs
///   nothing, because the fill is real.
///
/// Mounted with `.safeAreaInset(edge: .bottom)` rather than stacked over the
/// content, which is what makes it *reserve* its height instead of covering
/// things: `MapTab` reads `safeAreaInsets.bottom` to size its sheet, and that
/// keeps reporting the truth with no change on its side.
struct HooprTabBar: View {
    @Binding var selection: HooprTab

    /// Ceiling on the whole shelf's growth. Past roughly this, the labels stop
    /// scaling and the glyphs carry the size increase — the same trade Apple's
    /// own bar makes rather than letting the bar consume the screen.
    private let itemMinimumHeight: CGFloat = 44

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HooprTab.allCases, id: \.self) { tab in
                item(for: tab)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background {
            // The fill runs past the bottom safe area so the shelf reaches the
            // screen edge and the home indicator sits on it, rather than on a
            // strip of whatever is scrolling underneath.
            Color.hooprSurface
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.hooprBorder)
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func item(for tab: HooprTab) -> some View {
        let isSelected = selection == tab

        return Button {
            // Switching tabs is instant: the content swaps and the glyph turns
            // orange in the same frame. Killing the transaction is what stops
            // SwiftUI animating the selection change implicitly — a crossfade
            // between two full screens reads as lag, not polish.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selection = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.symbol)
                    .hooprFont(22, weight: .medium, maximumSize: 28)

                Text(tab.title)
                    .hooprFont(11, weight: isSelected ? .semibold : .medium, maximumSize: 14)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.hooprOrange : Color.hooprSecondaryText)
            .frame(maxWidth: .infinity)
            .frame(minHeight: itemMinimumHeight)
            // The whole cell takes the tap, not just the glyph and its label.
            .contentShape(Rectangle())
        }
        .buttonStyle(InertButtonStyle())
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A button style with **no** press feedback at all.
///
/// `.plain` still dims its label while held, which on a tab shelf reads as a
/// second, competing state alongside the orange — you press Map, Home fades,
/// and for an instant neither looks current. The only state a tab has is
/// selected or not.
private struct InertButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

#Preview {
    @Previewable @State var selection: HooprTab = .home

    VStack {
        Spacer()
        HooprTabBar(selection: $selection)
    }
    .background(Color.hooprBackground)
}
