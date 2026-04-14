@testable import NotchMusic
import XCTest

final class NotchGeometryTests: XCTestCase {

    func test_compactWindowFrame_widthMatchesConstant() {
        // NotchGeometry uses the primary screen at runtime.
        // We only verify the derived frame dimensions, not absolute coordinates.
        let geo = NotchGeometry()
        XCTAssertEqual(geo.compactWindowFrame.width, NotchGeometry.compactWidth)
        XCTAssertEqual(geo.compactWindowFrame.height, NotchGeometry.compactHeight)
    }

    func test_expandedWindowFrame_widthMatchesConstant() {
        let geo = NotchGeometry()
        XCTAssertEqual(geo.expandedWindowFrame.width, NotchGeometry.expandedWidth)
        XCTAssertEqual(geo.expandedWindowFrame.height, NotchGeometry.expandedHeight)
    }

    func test_compactPillIsCenteredOnNotch() {
        let geo = NotchGeometry()
        let notchMidX   = geo.notchFrame.midX
        let pillMidX    = geo.compactWindowFrame.midX
        XCTAssertEqual(notchMidX, pillMidX, accuracy: 1.0)
    }

    func test_expandedCardIsCenteredOnNotch() {
        let geo = NotchGeometry()
        let notchMidX = geo.notchFrame.midX
        let cardMidX  = geo.expandedWindowFrame.midX
        XCTAssertEqual(notchMidX, cardMidX, accuracy: 1.0)
    }
}
