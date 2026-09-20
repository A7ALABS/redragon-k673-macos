import Foundation

/// One key-matrix slot: [type, param, codeHi, codeLo].
/// type 0 = keyboard (param is a modifier bitmask, code a HID keyboard usage), 2 = consumer-page usage, 0x0d = Fn,
/// 8 = firmware lighting control (what Fn + arrows send).
public struct KeyAction: Equatable, Hashable, Sendable {
    public var raw: [UInt8]

    public init(raw: [UInt8]) { self.raw = raw }

    public static func key(_ usage: UInt8, modifiers: UInt8 = 0) -> KeyAction { KeyAction(raw: [0, modifiers, 0, usage]) }
    public static func consumer(_ usage: UInt16) -> KeyAction { KeyAction(raw: [2, 0, UInt8(usage >> 8), UInt8(usage & 0xff)]) }
    public static let fn = KeyAction(raw: [0x0d, 0, 0, 0])
    public static let disabled = KeyAction(raw: [0, 0, 0, 0])
    public static let backlightUp = KeyAction(raw: [8, 3, 1, 0])
    public static let backlightDown = KeyAction(raw: [8, 3, 2, 0])

    public var isFn: Bool { raw[0] == 0x0d }

    public var title: String {
        if let named = Self.catalog.first(where: { $0.action == self }) { return named.title }
        if raw[0] == 0, raw[1] != 0, raw[3] != 0 {
            let mods = Self.modifierNames.filter { raw[1] & $0.0 != 0 }.map(\.1)
            let base = Self.catalog.first { $0.action == .key(raw[3]) }?.title ?? String(format: "0x%02X", raw[3])
            return (mods + [base]).joined(separator: "+")
        }
        return "Raw " + raw.map { String(format: "%02X", $0) }.joined()
    }

    private static let modifierNames: [(UInt8, String)] = [
        (0x01, "LCtrl"), (0x02, "LShift"), (0x04, "LAlt"), (0x08, "LCmd"),
        (0x10, "RCtrl"), (0x20, "RShift"), (0x40, "RAlt"), (0x80, "RCmd"),
    ]

    public struct Named: Identifiable, Hashable, Sendable {
        public let group: String
        public let title: String
        public let action: KeyAction
        public var id: String { group + "/" + title }
    }

    public static let catalog: [Named] = {
        var out: [Named] = []
        for (i, c) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() {
            out.append(Named(group: "Letters", title: String(c), action: .key(UInt8(0x04 + i))))
        }
        for (i, c) in "1234567890".enumerated() {
            out.append(Named(group: "Digits", title: String(c), action: .key(UInt8(0x1e + i))))
        }
        let editing: [(String, UInt8)] = [
            ("Enter", 0x28), ("Esc", 0x29), ("Backspace", 0x2a), ("Tab", 0x2b), ("Space", 0x2c),
            ("-", 0x2d), ("=", 0x2e), ("[", 0x2f), ("]", 0x30), ("\\", 0x31), (";", 0x33), ("'", 0x34),
            ("`", 0x35), (",", 0x36), (".", 0x37), ("/", 0x38), ("Caps Lock", 0x39),
        ]
        out += editing.map { Named(group: "Editing", title: $0.0, action: .key($0.1)) }
        for i in 0..<12 { out.append(Named(group: "Function", title: "F\(i + 1)", action: .key(UInt8(0x3a + i)))) }
        for i in 0..<8 { out.append(Named(group: "Function", title: "F\(i + 13)", action: .key(UInt8(0x68 + i)))) }
        let nav: [(String, UInt8)] = [
            ("Print Screen", 0x46), ("Scroll Lock", 0x47), ("Pause", 0x48), ("Insert", 0x49), ("Home", 0x4a),
            ("Page Up", 0x4b), ("Delete", 0x4c), ("End", 0x4d), ("Page Down", 0x4e),
            ("Right", 0x4f), ("Left", 0x50), ("Down", 0x51), ("Up", 0x52), ("Menu", 0x65),
        ]
        out += nav.map { Named(group: "Navigation", title: $0.0, action: .key($0.1)) }
        out += modifierNames.map { Named(group: "Modifiers", title: $0.1, action: .key(0, modifiers: $0.0)) }
        out.append(Named(group: "Modifiers", title: "Fn", action: .fn))
        let media: [(String, UInt16)] = [
            ("Play/Pause", 0xcd), ("Next track", 0xb5), ("Previous track", 0xb6), ("Stop", 0xb7),
            ("Mute", 0xe2), ("Volume up", 0xe9), ("Volume down", 0xea),
            ("Brightness up", 0x6f), ("Brightness down", 0x70),
        ]
        out += media.map { Named(group: "Media", title: $0.0, action: .consumer($0.1)) }
        out.append(Named(group: "Backlight", title: "Backlight up", action: .backlightUp))
        out.append(Named(group: "Backlight", title: "Backlight down", action: .backlightDown))
        out.append(Named(group: "Other", title: "Disabled", action: .disabled))
        return out
    }()
}
