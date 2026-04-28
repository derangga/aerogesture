import AppKit
import ApplicationServices
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

enum GestureState {
    case began
    case ended
}

enum SwipeAxis {
    case undecided
    case horizontal
    case vertical
}

final class GestureDetector {
    var config: Config
    var onSwipe: ((Direction) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var accDisX: Float = 0
    private var accDisY: Float = 0
    private var prevTouchPositions: [String: NSPoint] = [:]
    private var state: GestureState = .ended
    private var swipeAxis: SwipeAxis = .undecided
    private var activeFingerCount: Int = 0
    private var gestureAlreadyFired: Bool = false

    init(config: Config) {
        self.config = config
    }

    func start() {
        guard eventTap == nil else { return }

        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: NSEvent.EventTypeMask.gesture.rawValue,
            callback: { proxy, type, cgEvent, userInfo in
                let detector = Unmanaged<GestureDetector>.fromOpaque(userInfo!)
                    .takeUnretainedValue()
                return detector.eventHandler(proxy: proxy, eventType: type, cgEvent: cgEvent)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap = eventTap else {
            fputs("aerogesture: failed to create event tap. Is Accessibility enabled?\n", stderr)
            exit(1)
        }

        runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            // CFMachPort doesn't need explicit close — it's invalidated when removed
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Event handling

    private func eventHandler(
        proxy: CGEventTapProxy,
        eventType: CGEventType,
        cgEvent: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if eventType.rawValue == NSEvent.EventType.gesture.rawValue,
           let nsEvent = NSEvent(cgEvent: cgEvent)
        {
            touchEventHandler(nsEvent)
        } else if eventType == .tapDisabledByUserInput || eventType == .tapDisabledByTimeout {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passUnretained(cgEvent)
    }

    private func touchEventHandler(_ nsEvent: NSEvent) {
        let touches = nsEvent.allTouches()
        if touches.isEmpty { return }

        let touchesCount = touches.allSatisfy({ $0.phase == .ended }) ? 0 : touches.count
        if touchesCount == 0 {
            stopGesture()
        } else {
            processTouches(touches: touches, count: touchesCount)
        }
    }

    private func stopGesture() {
        if state == .began {
            state = .ended
            if swipeAxis != .vertical && !gestureAlreadyFired {
                handleGesture()
            }
            clearEventState()
        }
    }

    private func processTouches(touches: Set<NSTouch>, count: Int) {
        let requiredFingers = config.gesture.fingers

        if state != .began && count == requiredFingers {
            state = .began
            activeFingerCount = count
        }
        if state == .began && swipeAxis == .undecided {
            activeFingerCount = count
        }

        guard state == .began else { return }

        let (disX, disY) = swipeDistance(touches: touches)
        accDisX += disX
        accDisY += disY

        // Lock axis once we have enough movement
        if swipeAxis == .undecided {
            let threshold = config.internalThreshold * 0.3
            if abs(accDisX) > threshold || abs(accDisY) > threshold {
                swipeAxis = abs(accDisY) > abs(accDisX) ? .vertical : .horizontal
            }
        }

        // Fire single workspace switch when threshold crossed
        if swipeAxis == .horizontal && !gestureAlreadyFired {
            let threshold = config.internalThreshold
            if abs(accDisX) >= threshold {
                gestureAlreadyFired = true
                let direction: Direction
                if config.gesture.naturalDirection {
                    direction = accDisX > 0 ? .prev : .next
                } else {
                    direction = accDisX > 0 ? .next : .prev
                }
                onSwipe?(direction)
            }
        }
    }

    private func handleGesture() {
        let threshold = config.internalThreshold
        guard abs(accDisX) >= threshold else { return }

        let direction: Direction
        if config.gesture.naturalDirection {
            direction = accDisX > 0 ? .prev : .next
        } else {
            direction = accDisX > 0 ? .next : .prev
        }
        onSwipe?(direction)
    }

    private func clearEventState() {
        accDisX = 0
        accDisY = 0
        swipeAxis = .undecided
        activeFingerCount = 0
        gestureAlreadyFired = false
        prevTouchPositions.removeAll()
    }

    // MARK: - Touch distance calculation

    private func swipeDistance(touches: Set<NSTouch>) -> (Float, Float) {
        var allRight = true
        var allLeft = true
        var allUp = true
        var allDown = true
        var sumDisX: Float = 0
        var sumDisY: Float = 0
        var activeTouches = 0

        for touch in touches {
            let (disX, disY) = touchDistance(touch)
            allRight = allRight && disX >= 0
            allLeft = allLeft && disX <= 0
            allUp = allUp && disY >= 0
            allDown = allDown && disY <= 0
            sumDisX += disX
            sumDisY += disY

            if touch.phase == .ended {
                prevTouchPositions.removeValue(forKey: "\(touch.identity)")
            } else {
                prevTouchPositions["\(touch.identity)"] = touch.normalizedPosition
                activeTouches += 1
            }
        }

        let count = max(activeTouches, 1)
        var resultX = sumDisX / Float(count)
        var resultY = sumDisY / Float(count)

        // All fingers must move in the same direction
        if !allRight && !allLeft { resultX = 0 }
        if !allUp && !allDown { resultY = 0 }

        return (resultX, resultY)
    }

    private func touchDistance(_ touch: NSTouch) -> (Float, Float) {
        guard let prevPosition = prevTouchPositions["\(touch.identity)"] else {
            return (0, 0)
        }
        let position = touch.normalizedPosition
        return (
            Float(position.x - prevPosition.x),
            Float(position.y - prevPosition.y)
        )
    }
}
