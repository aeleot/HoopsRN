import SwiftUI

/// Lays its children out left to right and starts a new line when the next one
/// doesn't fit — centring every child vertically within its line.
///
/// Written for Home's detail line (a status pill, spots left, distance), where
/// the two alternatives both failed:
///
/// - **A plain `HStack`** aligned a capsule badge against text of a different
///   height by its centre while the text beside it sat on its baseline, so the
///   pill read as sitting slightly off the line — which is what the user
///   caught.
/// - **`ViewThatFits` between a row and a column** jumps from one line to one
///   item per line the moment the row is a point too wide, so a single long
///   distance put every fact on its own line.
///
/// This wraps only what has to move, and centres each item on its line, so a
/// pill and a line of text share a centre however the line breaks.
///
/// Each child is measured at its ideal size and never compressed, so an item
/// can't break mid-word; one that is wider than the whole line on its own is
/// offered the full width and wraps inside itself instead of overflowing.
struct FlowLayout: Layout {
    var spacing: CGFloat = Spacing.md
    var lineSpacing: CGFloat = Spacing.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = arrange(subviews, in: proposal.width ?? .infinity)
        let height = lines.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, lines.count - 1))
        let width = lines.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY

        for line in arrange(subviews, in: bounds.width) {
            var x = bounds.minX

            for item in line.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (line.height - item.size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }

            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, in width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var line = Line()

        for (index, subview) in subviews.enumerated() {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > width {
                // Wider than a whole line by itself: give it the line and let
                // it wrap inside, rather than run off the edge.
                size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            }

            let widthWithItem = line.items.isEmpty ? size.width : line.width + spacing + size.width
            if !line.items.isEmpty && widthWithItem > width {
                lines.append(line)
                line = Line()
            }

            line.width = line.items.isEmpty ? size.width : line.width + spacing + size.width
            line.height = max(line.height, size.height)
            line.items.append((index, size))
        }

        if !line.items.isEmpty {
            lines.append(line)
        }
        return lines
    }
}
