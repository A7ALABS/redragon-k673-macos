import Foundation
import IOKit.hid

public enum K673Error: Error, LocalizedError {
    case notFound
    case inputMonitoringDenied
    case openFailed(IOReturn)
    case writeFailed(IOReturn)
    case timeout(command: UInt8)
    case rejected(command: UInt8)
    case keyboardOffline
    case badLength(expected: Int, got: Int)

    public var errorDescription: String? {
        switch self {
        case .notFound: return "2.4G receiver (3554:fa09) not found. Plug in the dongle and set the keyboard to 2.4G mode."
        case .inputMonitoringDenied: return "macOS blocked access to the receiver. Enable this app in System Settings → Privacy & Security → Input Monitoring, then relaunch it."
        case .openFailed(let r): return String(format: "Could not open the receiver (0x%08x).", r)
        case .writeFailed(let r): return String(format: "USB write failed (0x%08x).", r)
        case .timeout(let c): return "Keyboard did not answer command \(c). Is it switched on and in 2.4G mode?"
        case .rejected(let c): return "Keyboard rejected command \(c)."
        case .keyboardOffline: return "Receiver is plugged in but the keyboard is not connected to it."
        case .badLength(let e, let g): return "Unexpected data length: expected \(e), got \(g)."
        }
    }
}

final class HIDTransport {
    static let vendorID = 0x3554
    static let productID = 0xfa09
    static let usagePage = 0xff02
    static let reportID: UInt8 = 0x13
    static let reportLength = 20

    private let manager: IOHIDManager
    private var device: IOHIDDevice?
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private let cond = NSCondition()
    private var inbox: [[UInt8]] = []
    private var thread: Thread?
    private var runLoop: CFRunLoop?

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    deinit {
        close()
        inputBuffer.deallocate()
    }

    func open() throws {
        let match: [String: Any] = [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID,
            kIOHIDPrimaryUsagePageKey: Self.usagePage,
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let dev = set.first else {
            throw K673Error.notFound
        }
        let r = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        if r == kIOReturnNotPermitted {
            // The vendor interface shares a HID device with a keyboard collection, so TCC gates it; this call is what makes macOS show the prompt.
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            throw K673Error.inputMonitoringDenied
        }
        guard r == kIOReturnSuccess else { throw K673Error.openFailed(r) }
        device = dev

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(dev, inputBuffer, 64, { ctx, _, _, _, _, report, length in
            guard let ctx else { return }
            let me = Unmanaged<HIDTransport>.fromOpaque(ctx).takeUnretainedValue()
            me.cond.lock()
            me.inbox.append(Array(UnsafeBufferPointer(start: report, count: length)))
            me.cond.signal()
            me.cond.unlock()
        }, ctx)

        let ready = DispatchSemaphore(value: 0)
        let t = Thread { [weak self] in
            guard let self, let dev = self.device else { return }
            self.runLoop = CFRunLoopGetCurrent()
            IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            ready.signal()
            CFRunLoopRun()
        }
        t.name = "k673.hid"
        t.start()
        thread = t
        ready.wait()
    }

    func close() {
        guard let dev = device else { return }
        if let rl = runLoop {
            IOHIDDeviceUnscheduleFromRunLoop(dev, rl, CFRunLoopMode.defaultMode.rawValue)
            CFRunLoopStop(rl)
        }
        IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        device = nil
        runLoop = nil
    }

    func drain() {
        cond.lock()
        inbox.removeAll()
        cond.unlock()
    }

    func send(_ report: [UInt8]) throws {
        guard let dev = device else { throw K673Error.notFound }
        let r = report.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, CFIndex(Self.reportID), $0.baseAddress!, $0.count)
        }
        guard r == kIOReturnSuccess else { throw K673Error.writeFailed(r) }
    }

    /// Returns the next 0x13 report whose command byte matches, discarding anything else (the dongle also pushes unsolicited status reports).
    func receive(command: UInt8, timeout: TimeInterval) -> [UInt8]? {
        let deadline = Date().addingTimeInterval(timeout)
        cond.lock()
        defer { cond.unlock() }
        while true {
            while !inbox.isEmpty {
                let r = inbox.removeFirst()
                if r.count >= Self.reportLength, r[0] == Self.reportID, r[1] == command { return r }
            }
            if !cond.wait(until: deadline) { return nil }
        }
    }
}
