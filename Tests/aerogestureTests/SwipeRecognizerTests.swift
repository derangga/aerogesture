import XCTest
@testable import aerogesture

final class SwipeRecognizerTests: XCTestCase {
    private let threshold: Float = 0.05

    /// `count` fingers at x, spread vertically so ids differ.
    private func touches(_ count: Int, x: Float, y: Float = 0.5, phase: TouchSample.Phase = .active) -> [TouchSample] {
        (0..<count).map { TouchSample(id: $0, x: x, y: y + Float($0) * 0.01, phase: phase) }
    }

    private func feed(_ r: inout SwipeRecognizer, _ t: [TouchSample], fingers: Int = 3, natural: Bool = true) -> Direction? {
        r.feed(t, fingers: fingers, threshold: threshold, naturalDirection: natural)
    }

    func testSwipeRightIsPrevWithNaturalDirection() {
        var r = SwipeRecognizer()
        XCTAssertNil(feed(&r, touches(3, x: 0.2)))
        XCTAssertNil(feed(&r, touches(3, x: 0.22)))
        XCTAssertEqual(feed(&r, touches(3, x: 0.4)), .prev)
    }

    func testSwipeLeftIsNextWithNaturalDirection() {
        var r = SwipeRecognizer()
        _ = feed(&r, touches(3, x: 0.8))
        _ = feed(&r, touches(3, x: 0.78))
        XCTAssertEqual(feed(&r, touches(3, x: 0.6)), .next)
    }

    func testNaturalDirectionOffFlipsDirection() {
        var r = SwipeRecognizer()
        _ = feed(&r, touches(3, x: 0.2), natural: false)
        _ = feed(&r, touches(3, x: 0.22), natural: false)
        XCTAssertEqual(feed(&r, touches(3, x: 0.4), natural: false), .next)
    }

    func testFiresOncePerGesture() {
        var r = SwipeRecognizer()
        _ = feed(&r, touches(3, x: 0.2))
        _ = feed(&r, touches(3, x: 0.22))
        XCTAssertNotNil(feed(&r, touches(3, x: 0.4)))
        XCTAssertNil(feed(&r, touches(3, x: 0.6)))
    }

    func testFourFingersLandingThroughThreeDoesNotFire() {
        var r = SwipeRecognizer()
        _ = feed(&r, touches(3, x: 0.2))
        XCTAssertNil(feed(&r, touches(4, x: 0.3)))
        XCTAssertNil(feed(&r, touches(4, x: 0.5)))
        // Dropping back to three fingers must not restart the gesture
        XCTAssertNil(feed(&r, touches(3, x: 0.7)))
        XCTAssertNil(feed(&r, touches(3, x: 0.9)))
    }

    func testFourFingerSwipeFiresWhenConfiguredForFour() {
        var r = SwipeRecognizer()
        _ = feed(&r, touches(4, x: 0.2), fingers: 4)
        _ = feed(&r, touches(4, x: 0.22), fingers: 4)
        XCTAssertEqual(feed(&r, touches(4, x: 0.4), fingers: 4), .prev)
    }

    func testCancelledGestureThenTwoFingerScrollDoesNotFire() {
        var r = SwipeRecognizer()
        _ = feed(&r, touches(3, x: 0.2))
        XCTAssertNil(feed(&r, touches(3, x: 0.21, phase: .cancelled)))
        XCTAssertNil(feed(&r, touches(2, x: 0.3)))
        XCTAssertNil(feed(&r, touches(2, x: 0.6)))
    }

    func testEndedTouchesAreNotCounted() {
        var r = SwipeRecognizer()
        _ = feed(&r, touches(3, x: 0.2))
        // One finger lifts, two others keep moving: count differs from 3, so no swipe
        let t = touches(1, x: 0.3, phase: .ended) + touches(2, x: 0.5).map {
            TouchSample(id: $0.id + 10, x: $0.x, y: $0.y, phase: .active)
        }
        XCTAssertNil(feed(&r, t))
    }

    func testReleaseResetsForNextGesture() {
        var r = SwipeRecognizer()
        _ = feed(&r, touches(3, x: 0.2))
        _ = feed(&r, touches(3, x: 0.22))
        XCTAssertNotNil(feed(&r, touches(3, x: 0.4)))
        XCTAssertNil(feed(&r, touches(3, x: 0.4, phase: .ended)))
        _ = feed(&r, touches(3, x: 0.8))
        _ = feed(&r, touches(3, x: 0.78))
        XCTAssertEqual(feed(&r, touches(3, x: 0.6)), .next)
    }

    func testVerticalSwipeDoesNotFire() {
        var r = SwipeRecognizer()
        _ = feed(&r, touches(3, x: 0.5, y: 0.2))
        XCTAssertNil(feed(&r, touches(3, x: 0.5, y: 0.4)))
        XCTAssertNil(feed(&r, touches(3, x: 0.7, y: 0.45)))
    }

    func testTwoFingerScrollDoesNotFire() {
        var r = SwipeRecognizer()
        _ = feed(&r, touches(2, x: 0.2))
        XCTAssertNil(feed(&r, touches(2, x: 0.6)))
    }
}
