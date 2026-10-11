import AppKit
import ApplicationServices
import Foundation

final class GestureDetector {
    var config: Config
    var onSwipe: ((Direction) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var recognizer = SwipeRecognizer()

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
            CFMachPortInvalidate(tap)
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

        let samples = touches.map { touch in
            let phase: TouchSample.Phase
            if touch.phase == .ended {
                phase = .ended
            } else if touch.phase == .cancelled {
                phase = .cancelled
            } else {
                phase = .active
            }
            return TouchSample(
                id: touch.identity.hash,
                x: Float(touch.normalizedPosition.x),
                y: Float(touch.normalizedPosition.y),
                phase: phase
            )
        }

        if let direction = recognizer.feed(
            samples,
            fingers: config.gesture.fingers,
            threshold: config.internalThreshold,
            naturalDirection: config.gesture.naturalDirection
        ) {
            onSwipe?(direction)
        }
    }
}
