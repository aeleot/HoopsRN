// Draws the app's basketball-court glyph and writes it as a custom SF Symbol.
//
//     swift tools/make_court_symbol.swift
//     swift tools/make_court_symbol.swift --preview /tmp/court.png
//
// **Why this exists.** SF Symbols has no basketball court. The app used
// `sportscourt.fill`, which is a pitch — a box at each end — and reads as
// soccer. This draws the court a basketball player recognises: a three-point
// arc and the key at each end, the centre circle and the half-court line,
// knocked out of a filled tile the way `sportscourt.fill` is, so it sits in
// the same places at the same weight.
//
// It is a symbol rather than a shape so it sizes, aligns and colours exactly
// as the system glyph did: `.hooprType(_:)`, `firstTextBaseline`,
// `.foregroundStyle`. The markings are drawn as strokes and subtracted from the
// tile with Core Graphics' boolean operations (macOS 14+), so overlapping
// marks — the centre line through the circle — cut cleanly.
//
// The template holds one variant, Regular-M, which is the minimum Xcode
// accepts. The path carries no class and the file no `<style>`: the SF
// Symbols app's exports style paths as a preview wireframe (no fill, a thin
// black stroke), and an asset compiled with that style draws exactly that —
// a faint black outline that ignores `.foregroundStyle`. Every weight and
// scale draws the one variant; the knockouts don't need to thin with weight
// the way a stroked outline would.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The court in symbol units at 100pt: y grows downward, the baseline is 0,
/// and the cap height is 70.459 — the template's own guides.
struct CourtGlyph {
    let width: CGFloat = 128
    let top: CGFloat = -78
    let bottom: CGFloat = 6
    let cornerRadius: CGFloat = 12
    /// The width of a knocked-out line.
    let line: CGFloat = 7.5
    let centreCircleRadius: CGFloat = 12
    let arcRadius: CGFloat = 28
    /// How far the three-point line runs straight off the baseline before it
    /// curves, as the real one does.
    let arcStraight: CGFloat = 8
    let keyDepth: CGFloat = 18
    let keyHalfWidth: CGFloat = 8

    var midY: CGFloat { (top + bottom) / 2 }

    func path() -> CGPath {
        let tile = CGPath(
            roundedRect: CGRect(x: 0, y: top, width: width, height: bottom - top),
            cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil
        )

        let marks = CGMutablePath()
        // Past both edges, so the cut runs cleanly out of the tile.
        let overshoot: CGFloat = 4
        marks.move(to: CGPoint(x: width / 2, y: top - overshoot))
        marks.addLine(to: CGPoint(x: width / 2, y: bottom + overshoot))
        marks.addEllipse(in: CGRect(
            x: width / 2 - centreCircleRadius, y: midY - centreCircleRadius,
            width: centreCircleRadius * 2, height: centreCircleRadius * 2
        ))

        for isLeft in [true, false] {
            let direction: CGFloat = isLeft ? 1 : -1
            let baseline: CGFloat = isLeft ? 0 : width
            func x(_ depth: CGFloat) -> CGFloat { baseline + direction * depth }

            // The three-point line.
            marks.move(to: CGPoint(x: x(-overshoot), y: midY - arcRadius))
            marks.addLine(to: CGPoint(x: x(arcStraight), y: midY - arcRadius))
            marks.addArc(
                center: CGPoint(x: x(arcStraight), y: midY), radius: arcRadius,
                startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: !isLeft
            )
            marks.addLine(to: CGPoint(x: x(-overshoot), y: midY + arcRadius))

            // The key, open at the baseline.
            marks.move(to: CGPoint(x: x(-overshoot), y: midY - keyHalfWidth))
            marks.addLine(to: CGPoint(x: x(keyDepth), y: midY - keyHalfWidth))
            marks.addLine(to: CGPoint(x: x(keyDepth), y: midY + keyHalfWidth))
            marks.addLine(to: CGPoint(x: x(-overshoot), y: midY + keyHalfWidth))
        }

        let cuts = marks.copy(strokingWithWidth: line, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
        return tile.subtracting(cuts.normalized())
    }
}

func svgPathData(_ path: CGPath) -> String {
    func n(_ value: CGFloat) -> String {
        var text = String(format: "%.3f", Double(value))
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }
    var data = ""
    path.applyWithBlock { pointer in
        let element = pointer.pointee
        let p = element.points
        switch element.type {
        case .moveToPoint: data += "M\(n(p[0].x)) \(n(p[0].y))"
        case .addLineToPoint: data += "L\(n(p[0].x)) \(n(p[0].y))"
        case .addQuadCurveToPoint: data += "Q\(n(p[0].x)) \(n(p[0].y)) \(n(p[1].x)) \(n(p[1].y))"
        case .addCurveToPoint:
            data += "C\(n(p[0].x)) \(n(p[0].y)) \(n(p[1].x)) \(n(p[1].y)) \(n(p[2].x)) \(n(p[2].y))"
        case .closeSubpath: data += "Z"
        @unknown default: break
        }
    }
    return data
}

/// A version-3 symbol template carrying only Regular-M.
func template(pathData: String, glyphWidth: CGFloat) -> String {
    let rows: [(scale: String, baseline: Double)] = [("S", 696), ("M", 1126), ("L", 1556)]
    let originX = 1400.0, originY = 1126.0
    let sideBearing = 4.0
    let left = originX - sideBearing
    let right = originX + Double(glyphWidth) + sideBearing

    var guides = ""
    for row in rows {
        let capline = String(format: "%.3f", row.baseline - 70.459)
        guides += """
          <line id="Baseline-\(row.scale)" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="\(row.baseline)" y2="\(row.baseline)"/>
          <line id="Capline-\(row.scale)" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="\(capline)" y2="\(capline)"/>

        """
    }

    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE svg
    PUBLIC "-//W3C//DTD SVG 1.1//EN"
           "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
    <svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="3300" height="2200">
     <!--glyph: "", point size: 100.0, generated by tools/make_court_symbol.swift — edit that, not this-->
     <g id="Notes">
      <rect height="2200" id="artboard" style="fill:white;opacity:1" width="3300" x="0" y="0"/>
      <text id="template-version" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1933)">Template v.3.0</text>
     </g>
     <g id="Guides">
    \(guides)  <line id="left-margin-Regular-M" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="\(left)" x2="\(left)" y1="\(originY - 95)" y2="\(originY + 24)"/>
      <line id="right-margin-Regular-M" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="\(right)" x2="\(right)" y1="\(originY - 95)" y2="\(originY + 24)"/>
     </g>
     <g id="Symbols">
      <g id="Regular-M" transform="matrix(1 0 0 1 \(originX) \(originY))">
       <path d="\(pathData)"/>
      </g>
     </g>
    </svg>

    """
}

/// The glyph beside `sportscourt.fill` at the sizes the app draws it.
func writePreview(_ path: CGPath, glyph: CourtGlyph, to url: URL) {
    let sizes: [CGFloat] = [13, 17, 20, 28, 100]
    let scale: CGFloat = 3
    let width = 1500, height = 620
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    var x: CGFloat = 20
    for size in sizes {
        let k = size / 100 * scale
        context.saveGState()
        context.translateBy(x: x, y: 330)
        context.scaleBy(x: k, y: -k)
        context.addPath(path)
        context.setFillColor(CGColor(red: 0.93, green: 0.45, blue: 0.29, alpha: 1))
        context.fillPath()
        context.restoreGState()

        let config = NSImage.SymbolConfiguration(pointSize: size * scale, weight: .semibold)
        if let image = NSImage(systemSymbolName: "sportscourt.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            var rect = CGRect(origin: .zero, size: image.size)
            if let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                context.draw(cg, in: CGRect(x: x, y: 40, width: image.size.width, height: image.size.height))
            }
        }
        x += glyph.width * k + 40
    }

    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
}

let glyph = CourtGlyph()
let path = glyph.path()
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = root.appendingPathComponent("hoopr/Assets.xcassets/hoopr.court.fill.symbolset/hoopr.court.fill.svg")
try template(pathData: svgPathData(path), glyphWidth: glyph.width)
    .write(to: output, atomically: true, encoding: .utf8)
print("wrote \(output.path)")

if let flag = CommandLine.arguments.firstIndex(of: "--preview"), flag + 1 < CommandLine.arguments.count {
    let url = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
    writePreview(path, glyph: glyph, to: url)
    print("wrote \(url.path)")
}
