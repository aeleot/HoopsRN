import SwiftUI

/// Rows on the page with one hairline between each — the list primitive the UI
/// revamp uses in place of a card per row (archetype A2).
///
/// A container rather than a divider each caller places, so a conditional row
/// (a row that's only there for some accounts) can't leave a doubled or
/// dangling line: the rule goes *between* whatever rows are actually present.
/// Built on `Group(subviews:)`, iOS 18 — the app's floor.
///
/// `leadingInset` starts the hairline under the row's text rather than its
/// glyph or avatar, the way a system list does, so the leading column reads as
/// one column.
struct DividedRows<Content: View>: View {
    var leadingInset: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(Array(subviews.enumerated()), id: \.element.id) { index, subview in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.hooprBorder)
                            .frame(height: 1)
                            .padding(.leading, leadingInset)
                    }
                    subview
                }
            }
        }
    }
}
