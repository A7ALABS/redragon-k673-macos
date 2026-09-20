import Foundation

public struct RGB: Equatable, Hashable, Sendable {
    public var r, g, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }

    public init?(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(UInt8(v >> 16), UInt8(v >> 8 & 0xff), UInt8(v & 0xff))
    }

    public var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
    public static let black = RGB(0, 0, 0)
}

public struct Effect: Identifiable, Hashable, Sendable {
    public let id: UInt8
    public let name: String
    public let hasSpeed: Bool
    public let hasColor: Bool

    public static let off = Effect(id: 0, name: "Off", hasSpeed: false, hasColor: false)
    public static let custom = Effect(id: 19, name: "Custom (per-key)", hasSpeed: false, hasColor: false)

    public static let all: [Effect] = [
        Effect(id: 1, name: "Steady", hasSpeed: false, hasColor: true),
        Effect(id: 2, name: "Breathing", hasSpeed: true, hasColor: true),
        Effect(id: 3, name: "Rainbow", hasSpeed: true, hasColor: false),
        Effect(id: 4, name: "Flash away", hasSpeed: true, hasColor: true),
        Effect(id: 5, name: "Raindrops", hasSpeed: true, hasColor: true),
        Effect(id: 6, name: "Rainbow wheel", hasSpeed: true, hasColor: true),
        Effect(id: 7, name: "Ripples", hasSpeed: true, hasColor: true),
        Effect(id: 8, name: "Stars twinkle", hasSpeed: true, hasColor: true),
        Effect(id: 9, name: "Shadow disappear", hasSpeed: true, hasColor: true),
        Effect(id: 10, name: "Retro snake", hasSpeed: true, hasColor: true),
        Effect(id: 11, name: "Neon stream", hasSpeed: true, hasColor: true),
        Effect(id: 12, name: "Reaction", hasSpeed: true, hasColor: true),
        Effect(id: 13, name: "Sine wave", hasSpeed: true, hasColor: true),
        Effect(id: 14, name: "Retinue scanning", hasSpeed: true, hasColor: true),
        Effect(id: 15, name: "Rotating windmill", hasSpeed: true, hasColor: false),
        Effect(id: 16, name: "Colorful waterfall", hasSpeed: true, hasColor: false),
        Effect(id: 17, name: "Blossoming", hasSpeed: true, hasColor: false),
        Effect(id: 18, name: "Rotating storm", hasSpeed: true, hasColor: true),
        custom,
        off,
    ]

    public static func byID(_ id: UInt8) -> Effect? { all.first { $0.id == id } }
}

/// 128-byte settings block. Offsets verified against a K673 PRO over the 2.4G dongle.
public struct Profile: Equatable, Sendable {
    public static let length = 128
    public static let maxLevel: UInt8 = 4
    /// Color nibble value that tells the firmware to cycle colors instead of using palette slot 0.
    public static let multicolor: UInt8 = 7

    public var bytes: [UInt8]

    public init(bytes: [UInt8]) throws {
        guard bytes.count == Self.length else { throw K673Error.badLength(expected: Self.length, got: bytes.count) }
        self.bytes = bytes
    }

    public var effectID: UInt8 {
        get { bytes[10] }
        set {
            bytes[10] = newValue
            bytes[9] = newValue == Effect.custom.id ? 1 : 0
        }
    }

    private func paramOffset(_ effect: UInt8) -> Int? {
        let o = 56 + Int(effect) * 2
        return o + 1 < 126 ? o : nil
    }

    public func brightness(for effect: UInt8) -> UInt8 {
        paramOffset(effect).map { min(bytes[$0], Self.maxLevel) } ?? Self.maxLevel
    }

    public mutating func setBrightness(_ v: UInt8, for effect: UInt8) {
        guard let o = paramOffset(effect) else { return }
        bytes[o] = min(v, Self.maxLevel)
    }

    public func speed(for effect: UInt8) -> UInt8 {
        paramOffset(effect).map { min(bytes[$0 + 1] >> 4, Self.maxLevel) } ?? 2
    }

    public mutating func setSpeed(_ v: UInt8, for effect: UInt8) {
        guard let o = paramOffset(effect) else { return }
        bytes[o + 1] = (min(v, Self.maxLevel) << 4) | (bytes[o + 1] & 0x0f)
    }

    public func isMulticolor(for effect: UInt8) -> Bool {
        paramOffset(effect).map { bytes[$0 + 1] & 0x0f == Self.multicolor } ?? true
    }

    public mutating func setMulticolor(_ on: Bool, for effect: UInt8) {
        guard let o = paramOffset(effect) else { return }
        bytes[o + 1] = (bytes[o + 1] & 0xf0) | (on ? Self.multicolor : 0)
    }

    /// Backlight sleep timeout; the firmware counts in 30-second units, 0 disables sleep.
    public var sleepSeconds: Int {
        get { Int(bytes[24]) * 30 }
        set { bytes[24] = UInt8(clamping: newValue / 30) }
    }
}

/// Seven RGB slots per effect; slot 0 is the one used when an effect is in single-color mode.
public struct Palette: Equatable, Sendable {
    public static let length = 420
    public var bytes: [UInt8]

    public init(bytes: [UInt8]) throws {
        guard bytes.count >= Self.length else { throw K673Error.badLength(expected: Self.length, got: bytes.count) }
        self.bytes = Array(bytes.prefix(Self.length))
    }

    public func color(for effect: UInt8) -> RGB {
        let o = Int(effect) * 21
        guard o + 2 < bytes.count else { return RGB(255, 0, 0) }
        return RGB(bytes[o], bytes[o + 1], bytes[o + 2])
    }

    public mutating func setColor(_ c: RGB, for effect: UInt8) {
        let o = Int(effect) * 21
        guard o + 2 < bytes.count else { return }
        bytes[o] = c.r; bytes[o + 1] = c.g; bytes[o + 2] = c.b
    }
}

/// Per-key colors for the custom effect, stored planar: 126 reds, 126 greens, 126 blues.
public struct KeyColors: Equatable, Sendable {
    public static let slots = 126
    public var bytes: [UInt8]

    public init(bytes: [UInt8]) throws {
        guard bytes.count == Self.slots * 3 else { throw K673Error.badLength(expected: Self.slots * 3, got: bytes.count) }
        self.bytes = bytes
    }

    public init(fill: RGB) {
        bytes = [UInt8](repeating: fill.r, count: Self.slots) + [UInt8](repeating: fill.g, count: Self.slots) + [UInt8](repeating: fill.b, count: Self.slots)
    }

    public subscript(index: Int) -> RGB {
        get { RGB(bytes[index], bytes[index + Self.slots], bytes[index + 2 * Self.slots]) }
        set {
            bytes[index] = newValue.r
            bytes[index + Self.slots] = newValue.g
            bytes[index + 2 * Self.slots] = newValue.b
        }
    }
}

public struct KeyMatrix: Equatable, Sendable {
    public static let length = KeyColors.slots * 4
    public var bytes: [UInt8]

    public init(bytes: [UInt8]) throws {
        guard bytes.count == Self.length else { throw K673Error.badLength(expected: Self.length, got: bytes.count) }
        self.bytes = bytes
    }

    public static var factory: KeyMatrix { try! KeyMatrix(bytes: Defaults.baseMatrix) }

    public subscript(index: Int) -> KeyAction {
        get { KeyAction(raw: Array(bytes[index * 4..<index * 4 + 4])) }
        set { bytes.replaceSubrange(index * 4..<index * 4 + 4, with: newValue.raw) }
    }
}

public final class Keyboard {
    public struct Info: Sendable {
        public let firmware: String
        public let modelCode: UInt8
    }

    private enum Cmd {
        static let setKeyMatrix: UInt8 = 1
        static let setKeyColors: UInt8 = 2
        static let setProfile: UInt8 = 4
        static let getInfo: UInt8 = 5
        static let getStatus: UInt8 = 7
        static let setPalette: UInt8 = 9
        static let getKeyMatrix: UInt8 = 65
        static let getKeyColors: UInt8 = 66
        static let getProfile: UInt8 = 68
        static let getPalette: UInt8 = 73
    }

    private static let chunk = 14
    private let hid = HIDTransport()
    private let lock = NSLock()

    public init() {}

    public func open() throws { try hid.open() }
    public func close() { hid.close() }

    private func packet(_ cmd: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8, _ data: ArraySlice<UInt8> = []) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: HIDTransport.reportLength)
        p[0] = HIDTransport.reportID
        p[1] = cmd; p[2] = b1; p[3] = b2; p[4] = b3
        p.replaceSubrange(5..<5 + data.count, with: data)
        p[19] = p[0..<18].reduce(0, &+)
        return p
    }

    private func read(_ cmd: UInt8, b2: UInt8 = 0, b3: UInt8 = 0) throws -> [UInt8] {
        lock.lock(); defer { lock.unlock() }
        // The radio link occasionally drops a response packet and there is no per-packet re-request, so reassemble by index and redo the whole read on a gap.
        for _ in 0..<4 {
            hid.drain()
            try hid.send(packet(cmd, 1, b2, b3))
            var parts: [Int: ArraySlice<UInt8>] = [:]
            var total = 0
            while let r = hid.receive(command: cmd, timeout: 0.5) {
                total = Int(r[2] & 0x7f)
                let index = Int(r[3] & 0x7f)
                parts[index] = r[5..<5 + Int(r[4] & 0x0f)]
                if index >= total - 1 { break }
            }
            if total > 0, parts.count == total {
                return (0..<total).flatMap { parts[$0]! }
            }
        }
        throw K673Error.timeout(command: cmd)
    }

    private func write(_ cmd: UInt8, _ data: [UInt8], b2: UInt8 = 0, b3: UInt8 = 0) throws {
        lock.lock(); defer { lock.unlock() }
        hid.drain()
        let total = (data.count + Self.chunk - 1) / Self.chunk
        var index = 0, retries = 10
        while index < total {
            let slice = data[index * Self.chunk..<min(data.count, (index + 1) * Self.chunk)]
            try hid.send(packet(cmd, UInt8(total & 0x7f), UInt8(index & 0x7f) | b2, UInt8(slice.count & 0x0f) | b3, slice))
            // Bit 7 of the echoed packet count is the keyboard's NAK; the vendor app resends the same chunk.
            if let r = hid.receive(command: cmd, timeout: 1.0), r[2] & 0x80 == 0 {
                index += 1
            } else {
                retries -= 1
                if retries == 0 { throw K673Error.rejected(command: cmd) }
            }
        }
    }

    /// Single-packet query. The dongle drops a request that arrives while it is still relaying the previous exchange, so resend on silence.
    private func query(_ cmd: UInt8) throws -> [UInt8] {
        lock.lock(); defer { lock.unlock() }
        for _ in 0..<4 {
            hid.drain()
            try hid.send(packet(cmd, 1, 0, 0))
            if let r = hid.receive(command: cmd, timeout: 0.4) { return r }
        }
        throw K673Error.timeout(command: cmd)
    }

    public func isKeyboardOnline() throws -> Bool { try query(Cmd.getStatus)[5] > 0 }

    public func info() throws -> Info {
        let r = try query(Cmd.getInfo)
        return Info(firmware: String(format: "%02x%02x", r[13], r[14]), modelCode: r[10])
    }

    public func readProfile() throws -> Profile { try Profile(bytes: read(Cmd.getProfile)) }
    public func writeProfile(_ p: Profile) throws { try write(Cmd.setProfile, p.bytes) }

    public func readPalette() throws -> Palette { try Palette(bytes: read(Cmd.getPalette)) }
    public func writePalette(_ p: Palette) throws { try write(Cmd.setPalette, p.bytes) }

    public func readKeyColors() throws -> KeyColors { try KeyColors(bytes: read(Cmd.getKeyColors)) }
    public func writeKeyColors(_ c: KeyColors) throws { try write(Cmd.setKeyColors, c.bytes) }

    /// Base layer only. The protocol has a Windows/Mac table bit, but over the dongle both values address the same map.
    public func readKeyMatrix() throws -> KeyMatrix { try KeyMatrix(bytes: read(Cmd.getKeyMatrix)) }
    public func writeKeyMatrix(_ m: KeyMatrix) throws { try write(Cmd.setKeyMatrix, m.bytes) }
}
