import SwiftUI

/// The app's court glyph: a basketball court seen from above — the three-point
/// arc and the key at each end, the centre circle, the half-court line.
///
/// **A custom symbol, because SF Symbols has no basketball court.** The app
/// used `sportscourt.fill`, which draws a box at each end and reads as a
/// soccer pitch. This one is drawn by `tools/make_court_symbol.swift` into
/// `Assets.xcassets/hoopr.court.fill.symbolset` — regenerate it there rather
/// than editing the SVG — and it is a symbol rather than a `Shape` so it
/// sizes with `.hooprType(_:)`, sits on a text baseline and takes
/// `.foregroundStyle` exactly as the system glyph did.
///
/// It draws about **1.36× wider than its point size** (the old glyph was
/// 1.56×), which is what `CourtCardLayoutTests` measures the court name's room
/// against.
enum CourtSymbol {
    /// The asset's name — for UIKit, where `CourtCardLayoutTests` measures it.
    static let name = "hoopr.court.fill"
}

extension Image {
    /// The court glyph, decorative: every place it appears, the court's name
    /// is beside it and says what VoiceOver needs.
    static var court: Image { Image(decorative: CourtSymbol.name) }
}
