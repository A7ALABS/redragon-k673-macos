import AppKit
import IOKit.hid
import K673Kit

enum KnobMode: String, CaseIterable, Identifiable {
    case volume = "Volume"
    case screenBrightness = "Screen brightness"
    case backlight = "Keyboard backlight"

    var id: String { rawValue }
}

/// The firmware hardwires knob rotation to Volume Up/Down and ignores the key map for it, so the other modes are done on the host:
/// an event tap swallows volume keys that the dongle just sent and the chosen action runs instead.
final class KnobController {
    enum TapState { case off, active, needsAccessibility }

    var onTurn: ((_ clockwise: Bool) -> Void)?
    private(set) var tapState = TapState.off

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let lock = NSLock()
    private var lastKnobEvent = 0.0
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var swallowedDown: Set<Int> = []

    private static let volumeUp: UInt32 = 0xe9
    private static let volumeDown: UInt32 = 0xea
    private static let soundUpKey = 0
    private static let soundDownKey = 1
    private static let brightnessUpKey = 2
    private static let brightnessDownKey = 3
    private static let systemDefined = CGEventType(rawValue: 14)!
    private static let auxKeySubtype = 8

    init() {
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x3554, kIOHIDProductIDKey: 0xfa09] as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { ctx, _, _, value in
            let element = IOHIDValueGetElement(value)
            guard let ctx, IOHIDElementGetUsagePage(element) == 0x0c, IOHIDValueGetIntegerValue(value) == 1 else { return }
            let usage = IOHIDElementGetUsage(element)
            guard usage == KnobController.volumeUp || usage == KnobController.volumeDown else { return }
            let me = Unmanaged<KnobController>.fromOpaque(ctx).takeUnretainedValue()
            me.lock.lock()
            me.lastKnobEvent = CFAbsoluteTimeGetCurrent()
            me.lock.unlock()
            DispatchQueue.main.async { me.onTurn?(usage == KnobController.volumeUp) }
        }, ctx)
        // Own thread: the tap callback blocks the main run loop briefly while it waits for this callback to land.
        let thread = Thread { [manager] in
            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            CFRunLoopRun()
        }
        thread.name = "k673.knob"
        thread.start()
    }

    func setSuppressVolume(_ suppress: Bool) {
        if !suppress {
            if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
            swallowedDown.removeAll()
            tapState = .off
            return
        }
        if tap == nil { createTap() }
        guard let tap else {
            tapState = .needsAccessibility
            return
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        tapState = .active
    }

    private func createTap() {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(prompt) else { return }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: CGEventMask(1 << KnobController.systemDefined.rawValue),
                                callback: { _, type, event, ctx in
            guard let ctx else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<KnobController>.fromOpaque(ctx).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = me.tap, me.tapState == .active { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            return me.shouldSwallow(event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: ctx)
        guard let tap else { return }
        tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
    }

    private func shouldSwallow(_ event: CGEvent) -> Bool {
        guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == Self.auxKeySubtype else { return false }
        let key = (ns.data1 & 0xffff_0000) >> 16
        guard key == Self.soundUpKey || key == Self.soundDownKey else { return false }
        // A key-up must share its key-down's fate: passing one and swallowing the other leaves macOS believing the
        // volume key is held, which pins the volume HUD on screen.
        let isDown = (ns.data1 & 0xff00) >> 8 == 0xa
        guard isDown else { return swallowedDown.remove(key) != nil }
        let swallow = cameFromKnob()
        if swallow { swallowedDown.insert(key) } else { swallowedDown.remove(key) }
        return swallow
    }

    private func cameFromKnob() -> Bool {
        // The HID callback and the tap race on the same keystroke; give the callback a moment before deciding the key came from elsewhere.
        for _ in 0..<10 {
            lock.lock()
            let age = CFAbsoluteTimeGetCurrent() - lastKnobEvent
            lock.unlock()
            if age < 0.12 { return true }
            usleep(4000)
        }
        return false
    }

    static func postScreenBrightness(up: Bool) {
        let key = up ? brightnessUpKey : brightnessDownKey
        for state in [0xa, 0xb] {
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                                           timestamp: 0, windowNumber: 0, context: nil, subtype: Int16(auxKeySubtype),
                                           data1: (key << 16) | (state << 8), data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
