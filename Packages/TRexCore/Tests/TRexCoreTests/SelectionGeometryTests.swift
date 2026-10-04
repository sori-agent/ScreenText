import CoreGraphics
import XCTest
@testable import TRexCore

final class SelectionGeometryTests: XCTestCase {
    func testHandlePositionsUseCocoaTopAndBottomEdges() {
        let rect = CGRect(x: 30, y: 40, width: 100, height: 80)
        let expected: [(SelectionHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: 30, y: 120)), (.top, CGPoint(x: 80, y: 120)),
            (.topRight, CGPoint(x: 130, y: 120)), (.right, CGPoint(x: 130, y: 80)),
            (.bottomRight, CGPoint(x: 130, y: 40)), (.bottom, CGPoint(x: 80, y: 40)),
            (.bottomLeft, CGPoint(x: 30, y: 40)), (.left, CGPoint(x: 30, y: 80))
        ]
        for (handle, point) in expected {
            XCTAssertEqual(SelectionGeometry.position(of: handle, in: rect), point, "\(handle)")
        }
    }

    func testResizingRightKeepsOtherEdgesAnchored() {
        let rect = CGRect(x: 30, y: 40, width: 100, height: 80)
        let bounds = CGRect(x: 10, y: 20, width: 300, height: 200)

        XCTAssertEqual(
            SelectionGeometry.resized(rect, handle: .right, to: CGPoint(x: 200, y: 200), within: bounds),
            CGRect(x: 30, y: 40, width: 170, height: 80)
        )
    }

    func testMovementClampsToNonzeroBoundsWithoutChangingSize() {
        let rect = CGRect(x: 30, y: 40, width: 60, height: 50)
        let bounds = CGRect(x: 10, y: 20, width: 200, height: 160)

        XCTAssertEqual(SelectionGeometry.moved(rect, by: CGSize(width: -1000, height: -1000), within: bounds),
                       CGRect(x: 10, y: 20, width: 60, height: 50))
        XCTAssertEqual(SelectionGeometry.moved(rect, by: CGSize(width: 1000, height: 1000), within: bounds),
                       CGRect(x: 150, y: 130, width: 60, height: 50))
        XCTAssertEqual(SelectionGeometry.moved(rect, by: CGSize(width: 7, height: -9), within: bounds),
                       CGRect(x: 37, y: 31, width: 60, height: 50))
    }

    func testRetinaCropFlipsYAndSubtractsViewBoundsOrigin() {
        XCTAssertEqual(
            SelectionGeometry.pixelCrop(for: CGRect(x: 35, y: 40, width: 60, height: 30),
                                        viewBounds: CGRect(x: 10, y: 20, width: 200, height: 100),
                                        imageSize: CGSize(width: 400, height: 200)),
            CGRect(x: 50, y: 100, width: 120, height: 60)
        )
    }

    func testAllHandlesStopAtMinimumSizeWithoutFlipping() {
        let rect = CGRect(x: 30, y: 40, width: 100, height: 80)
        let bounds = CGRect(x: 10, y: 20, width: 300, height: 200)
        let cases: [(SelectionHandle, CGPoint, CGRect)] = [
            (.topLeft, CGPoint(x: 1000, y: -1000), CGRect(x: 106, y: 40, width: 24, height: 24)),
            (.top, CGPoint(x: 1000, y: -1000), CGRect(x: 30, y: 40, width: 100, height: 24)),
            (.topRight, CGPoint(x: -1000, y: -1000), CGRect(x: 30, y: 40, width: 24, height: 24)),
            (.right, CGPoint(x: -1000, y: 1000), CGRect(x: 30, y: 40, width: 24, height: 80)),
            (.bottomRight, CGPoint(x: -1000, y: 1000), CGRect(x: 30, y: 96, width: 24, height: 24)),
            (.bottom, CGPoint(x: 1000, y: 1000), CGRect(x: 30, y: 96, width: 100, height: 24)),
            (.bottomLeft, CGPoint(x: 1000, y: 1000), CGRect(x: 106, y: 96, width: 24, height: 24)),
            (.left, CGPoint(x: 1000, y: -1000), CGRect(x: 106, y: 40, width: 24, height: 80))
        ]
        for (handle, point, expected) in cases {
            XCTAssertEqual(SelectionGeometry.resized(rect, handle: handle, to: point, within: bounds),
                           expected, "\(handle)")
        }
    }

    func testCornerResizeClampsToBoundsAndKeepsOppositeCorner() {
        let rect = CGRect(x: 30, y: 40, width: 100, height: 80)
        let bounds = CGRect(x: 10, y: 20, width: 200, height: 160)
        let cases: [(SelectionHandle, CGPoint, CGRect)] = [
            (.topLeft, CGPoint(x: -1000, y: 1000), CGRect(x: 10, y: 40, width: 120, height: 140)),
            (.topRight, CGPoint(x: 1000, y: 1000), CGRect(x: 30, y: 40, width: 180, height: 140)),
            (.bottomRight, CGPoint(x: 1000, y: -1000), CGRect(x: 30, y: 20, width: 180, height: 100)),
            (.bottomLeft, CGPoint(x: -1000, y: -1000), CGRect(x: 10, y: 20, width: 120, height: 100))
        ]
        for (handle, point, expected) in cases {
            XCTAssertEqual(SelectionGeometry.resized(rect, handle: handle, to: point, within: bounds),
                           expected, "\(handle)")
        }
    }

    func testCustomMinimumSizeKeepsOppositeCorner() {
        XCTAssertEqual(
            SelectionGeometry.resized(CGRect(x: 30, y: 40, width: 100, height: 80), handle: .bottomLeft,
                                      to: CGPoint(x: 1000, y: 1000),
                                      within: CGRect(x: 10, y: 20, width: 300, height: 200),
                                      minimumSize: CGSize(width: 50, height: 30)),
            CGRect(x: 80, y: 90, width: 50, height: 30)
        )
    }

    func testMovementFitsSelectionAfterBoundsShrink() {
        XCTAssertEqual(
            SelectionGeometry.moved(CGRect(x: 0, y: 0, width: 500, height: 500), by: .zero,
                                    within: CGRect(x: 10, y: 20, width: 200, height: 160)),
            CGRect(x: 10, y: 20, width: 200, height: 160)
        )
    }

    func testCropClipsSelectionToImageBounds() {
        XCTAssertEqual(
            SelectionGeometry.pixelCrop(for: CGRect(x: -20, y: 90, width: 80, height: 80),
                                        viewBounds: CGRect(x: 10, y: 20, width: 200, height: 100),
                                        imageSize: CGSize(width: 400, height: 200)),
            CGRect(x: 0, y: 0, width: 100, height: 60)
        )
    }

    func testFractionalCropExcludesPixelsOutsideSelection() {
        XCTAssertEqual(
            SelectionGeometry.pixelCrop(for: CGRect(x: 10.2, y: 20.3, width: 10.6, height: 5.6),
                                        viewBounds: CGRect(x: 10, y: 20, width: 100, height: 50),
                                        imageSize: CGSize(width: 200, height: 100)),
            CGRect(x: 1, y: 89, width: 20, height: 10)
        )
    }

    func testOutsideAndSubpixelSelectionsHaveNoCrop() {
        let bounds = CGRect(x: 10, y: 20, width: 100, height: 50)
        let imageSize = CGSize(width: 200, height: 100)
        XCTAssertTrue(SelectionGeometry.pixelCrop(for: CGRect(x: -50, y: -50, width: 5, height: 5),
                                                 viewBounds: bounds, imageSize: imageSize).isNull)
        XCTAssertTrue(SelectionGeometry.pixelCrop(for: CGRect(x: 10.1, y: 20.1, width: 0.1, height: 0.1),
                                                 viewBounds: bounds, imageSize: imageSize).isNull)
    }
}
