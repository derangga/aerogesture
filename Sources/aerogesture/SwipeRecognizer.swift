import Foundation

enum Direction {
    case next
    case prev

    var value: String {
        switch self {
        case .next: "next"
        case .prev: "prev"
        }
    }
}

enum SwipeAxis {
    case undecided
    case horizontal
    case vertical
}

/// One finger on the trackpad, already stripped of AppKit types.
struct TouchSample {
    enum Phase {
        case active
        case ended
        case cancelled
    }

    let id: Int
    let x: Float
    let y: Float
    let phase: Phase
}

/// Pure state machine. Feed it every touch event, it returns a direction at most once per gesture.
struct SwipeRecognizer {
    private enum State {
        case idle
        case tracking
        /// Fired or cancelled. Ignore touches until every finger lifts.
        case finished
    }

    private var state: State = .idle
    private var accDisX: Float = 0
    private var accDisY: Float = 0
    private var axis: SwipeAxis = .undecided
    private var prevPositions: [Int: (x: Float, y: Float)] = [:]

    mutating func feed(
        _ touches: [TouchSample],
        fingers: Int,
        threshold: Float,
        naturalDirection: Bool
    ) -> Direction? {
        let active = touches.filter { $0.phase == .active }
        if active.isEmpty {
            reset()
            return nil
        }

        switch state {
        case .idle:
            guard active.count == fingers else { return nil }
            state = .tracking
        case .tracking:
            if active.count != fingers {
                clearMotion()
                state = .finished
                return nil
            }
        case .finished:
            return nil
        }

        for touch in touches where touch.phase != .active {
            prevPositions.removeValue(forKey: touch.id)
        }
        let (disX, disY) = swipeDistance(active)
        accDisX += disX
        accDisY += disY

        // Lock axis once we have enough movement
        if axis == .undecided {
            let lockThreshold = threshold * 0.3
            if abs(accDisX) > lockThreshold || abs(accDisY) > lockThreshold {
                axis = abs(accDisY) > abs(accDisX) ? .vertical : .horizontal
            }
        }

        guard axis == .horizontal, abs(accDisX) >= threshold else { return nil }

        let direction: Direction
        if naturalDirection {
            direction = accDisX > 0 ? .prev : .next
        } else {
            direction = accDisX > 0 ? .next : .prev
        }
        clearMotion()
        state = .finished
        return direction
    }

    private mutating func reset() {
        clearMotion()
        state = .idle
    }

    private mutating func clearMotion() {
        accDisX = 0
        accDisY = 0
        axis = .undecided
        prevPositions.removeAll()
    }

    private mutating func swipeDistance(_ active: [TouchSample]) -> (Float, Float) {
        var allRight = true
        var allLeft = true
        var allUp = true
        var allDown = true
        var sumDisX: Float = 0
        var sumDisY: Float = 0

        for touch in active {
            var disX: Float = 0
            var disY: Float = 0
            if let prev = prevPositions[touch.id] {
                disX = touch.x - prev.x
                disY = touch.y - prev.y
            }
            prevPositions[touch.id] = (touch.x, touch.y)

            allRight = allRight && disX >= 0
            allLeft = allLeft && disX <= 0
            allUp = allUp && disY >= 0
            allDown = allDown && disY <= 0
            sumDisX += disX
            sumDisY += disY
        }

        var resultX = sumDisX / Float(active.count)
        var resultY = sumDisY / Float(active.count)

        // All fingers must move in the same direction
        if !allRight && !allLeft { resultX = 0 }
        if !allUp && !allDown { resultY = 0 }

        return (resultX, resultY)
    }
}
