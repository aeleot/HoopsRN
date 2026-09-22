import XCTest
@testable import hoopr

/// Fails when a view draws `hooprOrange` as a **mark** — text, a glyph, a stroke,
/// a control tint — instead of `hooprBrandAccent`.
///
/// **Why this is a source scan.** The AA gap this closes survived for weeks
/// because nothing enforced the rule: `hooprOrange` measures 3.17:1 on white, so
/// it fails as a foreground, and it was reached for as a foreground 49 times
/// across 22 files because it is *the brand colour*. A contrast test on the role
/// cannot see a call site. This reads the real `Views/` tree, the same way
/// `FirestoreRulesParityTests` reads the real `firestore.rules`.
///
/// **It flags the mark, not the colour.** `hooprOrange` is still the right
/// colour for a *fill* — a button, a selected chip, the tint on active glass, a
/// low-opacity wash — because `hooprOnBrand` on it clears 6.62:1. So only the
/// modifiers that paint a mark are scanned: `foregroundStyle`, `foregroundColor`,
/// `tint`, `stroke`, `strokeBorder`. Adding a new orange button never trips it.
///
/// The parentheses are balanced rather than matched on one line, because a
/// ternary is routinely wrapped —
/// `.foregroundStyle(⏎ isOn ⏎ ? Color.hooprOrange ⏎ : …)` — and a per-line scan
/// misses exactly that shape (`QueueSheet`'s selected court did).
///
/// If this fails on a line you meant: `hooprBrandAccent` is the same orange,
/// deepened until it reads. If the orange really is a *fill* that this
/// mistakes for a mark, say so in the message and add the spelling to
/// `markModifiers`' exclusions rather than deleting the test.
final class BrandMarkUsageTests: XCTestCase {

    /// The modifiers whose argument is the colour a mark is drawn in.
    private static let markModifiers = ["foregroundStyle", "foregroundColor", "tint", "stroke", "strokeBorder"]

    private var viewsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // hooprTests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("hoopr/Views")
    }

    private func swiftFiles(under directory: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// Source with `//` comments blanked out (kept as spaces, so offsets and
    /// line numbers survive) — doc comments here *quote* the spelling they
    /// forbid, and would otherwise fail the test that enforces them.
    private func codeOnly(_ source: String) -> String {
        source
            .components(separatedBy: "\n")
            .map { line -> String in
                guard let range = line.range(of: "//") else { return line }
                // A `//` inside a string literal ("https://…") isn't a comment;
                // nothing under Views/ has one near these modifiers, but stay
                // honest about it.
                let prefix = line[..<range.lowerBound]
                if prefix.filter({ $0 == "\"" }).count % 2 == 1 { return line }
                return String(prefix) + String(repeating: " ", count: line.distance(from: range.lowerBound, to: line.endIndex))
            }
            .joined(separator: "\n")
    }

    /// The text between the parentheses opened at `openIndex`, or `nil` if they
    /// never close.
    private func balancedBody(in code: String, openIndex: String.Index) -> String? {
        var depth = 0
        var body = ""
        var index = openIndex
        while index < code.endIndex {
            let character = code[index]
            if character == "(" {
                depth += 1
                if depth == 1 {
                    index = code.index(after: index)
                    continue
                }
            } else if character == ")" {
                depth -= 1
                if depth == 0 { return body }
            }
            body.append(character)
            index = code.index(after: index)
        }
        return nil
    }

    private func violations(in source: String) -> [(line: Int, text: String)] {
        let code = codeOnly(source)
        var found: [(Int, String)] = []

        for modifier in Self.markModifiers {
            let needle = "." + modifier + "("
            var searchStart = code.startIndex
            while let hit = code.range(of: needle, range: searchStart..<code.endIndex) {
                let open = code.index(before: hit.upperBound)
                if let body = balancedBody(in: code, openIndex: open), body.contains("hooprOrange") {
                    let line = code[..<hit.lowerBound].reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
                    let flat = body
                        .split(whereSeparator: \.isNewline)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .joined(separator: " ")
                    found.append((line, ".\(modifier)(\(flat))"))
                }
                searchStart = hit.upperBound
            }
        }
        return found.sorted { $0.0 < $1.0 }
    }

    /// The scan must be able to fail. A guard that has never been shown a
    /// violation is a guard nobody knows works — and this one would report a
    /// clean tree if `viewsDirectory` resolved to nothing.
    func testTheScannerCatchesTheShapesItExistsFor() {
        let bad = """
        Text("x").foregroundStyle(Color.hooprOrange)
        Circle().stroke(Color.hooprOrange, lineWidth: 2)
        ProgressView().tint(Color.hooprOrange)
        Image(systemName: "checkmark")
            .foregroundStyle(
                isSelected
                    ? Color.hooprOrange
                    : Color.hooprSecondaryText
            )
        """
        XCTAssertEqual(violations(in: bad).count, 4, "the scanner should flag all four shapes, including the wrapped ternary")

        let fine = """
        Capsule().fill(Color.hooprOrange)
        Text("x").foregroundStyle(Color.hooprBrandAccent)
        Circle().fill(Color.hooprOrange.opacity(0.14))
        Button {} label: {}.background(Color.hooprOrange)
        .hooprGlass(tint: isActive ? Color.hooprOrange : nil, in: .capsule)
        // .foregroundStyle(Color.hooprOrange) — a comment quoting the rule
        """
        XCTAssertEqual(violations(in: fine).count, 0, "fills, washes, glass tints and comments must never trip it")
    }

    func testNoViewDrawsHooprOrangeAsAMark() throws {
        let files = swiftFiles(under: viewsDirectory)
        XCTAssertGreaterThan(files.count, 20, "Couldn't find hoopr/Views next to the source tree — the scan is unverified.")

        var report: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for violation in violations(in: source) {
                report.append("\(file.lastPathComponent):\(violation.line)  \(violation.text)")
            }
        }

        XCTAssertTrue(
            report.isEmpty,
            """
            hooprOrange is a fill — it measures 3.17:1 on white, under the 4.5:1 a mark needs. \
            Draw text, glyphs, strokes and control tints in hooprBrandAccent (same hue, deepened), \
            and keep hooprOrange for fills that carry hooprOnBrand:

            \(report.joined(separator: "\n"))
            """
        )
    }
}
