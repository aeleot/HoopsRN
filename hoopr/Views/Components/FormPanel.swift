import SwiftUI

/// A group of form rows on one panel, with a hairline between each — the
/// inset-grouped structure of an iOS form, drawn in the app's own roles.
///
/// It sits on `hooprGroupedBackground` and is filled with `hooprSurface`, so
/// the panel is told from the page by its fill alone: no edge and no shadow,
/// which is what keeps a stack of them from reading as cards. The rows inside
/// supply their own padding; `leadingInset` starts each hairline under the
/// row's text rather than its glyph, as `DividedRows` does on a page.
///
/// Built for `CreateGameSheet` (the user's call, 2026-09-23: the sheet "does
/// not seem very structured" — one form of free-standing sections, each with
/// its own visual grammar, and captions carrying what icons could).
struct FormPanel<Content: View>: View {
    static var cornerRadius: CGFloat { 14 }

    var leadingInset: CGFloat = FormRowMetrics.textInset
    @ViewBuilder var content: Content

    var body: some View {
        DividedRows(leadingInset: leadingInset) {
            content
        }
        .background(Color.hooprSurface, in: RoundedRectangle(cornerRadius: Self.cornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
    }
}

/// The measurements every row in a `FormPanel` shares, so a panel's glyphs
/// line up in one column and its hairlines start under one edge.
enum FormRowMetrics {
    static let horizontalPadding: CGFloat = Spacing.lg
    static let verticalPadding: CGFloat = Spacing.md
    /// The glyph column. The glyph is capped so it fits the column at every
    /// text size; the court glyph, which is wider than it is tall, is set
    /// smaller for the same reason (`FormRowGlyph`).
    static let glyphColumn: CGFloat = 28
    static let glyphGap: CGFloat = 14
    /// A row is never shorter than a touch target plus its padding.
    static let minimumHeight: CGFloat = 52
    static var textInset: CGFloat { horizontalPadding + glyphColumn + glyphGap }
}

/// A row's leading glyph, in the accent, in the fixed column.
struct FormRowGlyph: View {
    let image: Image
    /// The court glyph is landscape — about 1.36× wider than its size — so it
    /// is set smaller to keep inside the column.
    var isLandscape = false

    init(systemName: String) {
        image = Image(systemName: systemName)
    }

    init(_ image: Image, isLandscape: Bool) {
        self.image = image
        self.isLandscape = isLandscape
    }

    var body: some View {
        image
            .hooprFont(isLandscape ? 14 : 17, weight: .semibold, maximumSize: isLandscape ? 19 : 24)
            .foregroundStyle(Color.hooprBrandAccent)
            .frame(width: FormRowMetrics.glyphColumn)
            .accessibilityHidden(true)
    }
}

/// A panel row: the glyph, the title, and whatever the row ends with — a
/// value, a stepper. On one line when it fits; at the largest text sizes the
/// trailing part moves under the title rather than squeezing it.
struct FormRow<Title: View, Trailing: View>: View {
    let glyph: FormRowGlyph
    @ViewBuilder var title: Title
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: FormRowMetrics.glyphGap) {
            glyph

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.sm) {
                    title
                    Spacer(minLength: Spacing.sm)
                    trailing
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    title
                    trailing
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, FormRowMetrics.horizontalPadding)
        .padding(.vertical, FormRowMetrics.verticalPadding)
        .frame(maxWidth: .infinity, minHeight: FormRowMetrics.minimumHeight, alignment: .leading)
        .contentShape(Rectangle())
    }
}

extension FormRow where Trailing == EmptyView {
    init(glyph: FormRowGlyph, @ViewBuilder title: () -> Title) {
        self.glyph = glyph
        self.title = title()
        self.trailing = EmptyView()
    }
}
