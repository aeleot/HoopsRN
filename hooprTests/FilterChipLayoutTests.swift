import XCTest
import SwiftUI
import UIKit
@testable import hoopr

@MainActor
final class FilterChipLayoutTests: XCTestCase {
    func testCompactChipsKeepAFullTapTargetAtEveryTextSize() {
        for size in [DynamicTypeSize.large, .accessibility3, .accessibility5] {
            for filter in CourtFilter.allCases {
                for active in [false, true] {
                    let host = UIHostingController(rootView:
                        FilterChip(symbolName: filter.symbolName, label: filter.label,
                                   isActive: active, action: {})
                            .dynamicTypeSize(size)
                    )
                    let measured = host.sizeThatFits(in: CGSize(width: 1000, height: 1000))
                    XCTAssertGreaterThanOrEqual(measured.height, 44, "\(filter) at \(size)")
                    XCTAssertGreaterThanOrEqual(measured.width, 44)
                    let fontSize = HooprFontMetrics.scaledSize(HooprTextRole.caption.size,
                        at: HooprFontMetrics.contentSizeCategory(for: size))
                    let lineHeight = UIFont.systemFont(ofSize: fontSize, weight: .semibold).lineHeight
                    XCTAssertGreaterThanOrEqual(measured.height + 1, lineHeight + Spacing.xs * 2)
                }
            }
        }
    }
}
