import Foundation
import K673Kit

let usage = """
k673ctl — Redragon K673 PRO configuration (2.4G dongle)

  k673ctl status
  k673ctl effects
  k673ctl effect <id|name> [--brightness 0-4] [--speed 0-4] [--color RRGGBB | --multicolor]
  k673ctl brightness <0-4>
  k673ctl speed <0-4>
  k673ctl color <RRGGBB>                 single color for the current effect
  k673ctl key-color <RRGGBB> [key ...]   paint keys (all keys if none given) and switch to custom mode
  k673ctl sleep <seconds|off>            backlight sleep timeout (30 s steps)
  k673ctl keys                           list key names
  k673ctl remap <key> <action>           e.g. remap CapsLock LCtrl
  k673ctl remap-reset [key]
  k673ctl actions                        list assignable actions
  k673ctl backup <file.json>
  k673ctl restore <file.json>
"""

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

func level(_ s: String?) -> UInt8 {
    guard let s, let v = UInt8(s), v <= Profile.maxLevel else { fail("Expected a level from 0 to \(Profile.maxLevel).") }
    return v
}

func color(_ s: String?) -> RGB {
    guard let s, let c = RGB(hex: s) else { fail("Expected a color like FF8800.") }
    return c
}

func findKey(_ name: String) -> KeyDef {
    guard let k = Layout.keys.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
        fail("Unknown key '\(name)'. Run `k673ctl keys`.")
    }
    return k
}

func findEffect(_ s: String) -> Effect {
    if let id = UInt8(s), let e = Effect.byID(id) { return e }
    let needle = s.lowercased()
    guard let e = Effect.all.first(where: { $0.name.lowercased().hasPrefix(needle) }) else {
        fail("Unknown effect '\(s)'. Run `k673ctl effects`.")
    }
    return e
}

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { print(usage); exit(0) }
args.removeFirst()

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...i + 1)
    return v
}

func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}

switch command {
case "effects":
    for e in Effect.all { print(String(format: "%2d  %@", e.id, e.name)) }
    exit(0)
case "keys":
    print(Layout.keys.map(\.name).joined(separator: " "))
    exit(0)
case "actions":
    for (group, items) in Dictionary(grouping: KeyAction.catalog, by: \.group).sorted(by: { $0.key < $1.key }) {
        print("\(group): " + items.map(\.title).joined(separator: " "))
    }
    exit(0)
case "help", "-h", "--help":
    print(usage)
    exit(0)
default:
    break
}

let kb = Keyboard()
do {
    try kb.open()
    guard try kb.isKeyboardOnline() else { throw K673Error.keyboardOffline }

    switch command {
    case "status":
        let info = try kb.info()
        let p = try kb.readProfile()
        let e = Effect.byID(p.effectID)
        print("Firmware:   \(info.firmware) (model code \(String(format: "%02x", info.modelCode)))")
        print("Effect:     \(p.effectID) \(e?.name ?? "unknown")")
        print("Brightness: \(p.brightness(for: p.effectID))/\(Profile.maxLevel)")
        print("Speed:      \(p.speed(for: p.effectID))/\(Profile.maxLevel)")
        print("Color:      \(p.isMulticolor(for: p.effectID) ? "multicolor" : try kb.readPalette().color(for: p.effectID).hex)")
        print("Sleep:      \(p.sleepSeconds == 0 ? "off" : "\(p.sleepSeconds) s")")

    case "effect":
        guard let name = args.first else { fail(usage) }
        let e = findEffect(name)
        var p = try kb.readProfile()
        p.effectID = e.id
        if let b = option("--brightness") { p.setBrightness(level(b), for: e.id) }
        if let s = option("--speed") { p.setSpeed(level(s), for: e.id) }
        if let c = option("--color") {
            var pal = try kb.readPalette()
            pal.setColor(color(c), for: e.id)
            try kb.writePalette(pal)
            p.setMulticolor(false, for: e.id)
        } else if flag("--multicolor") {
            p.setMulticolor(true, for: e.id)
        }
        try kb.writeProfile(p)

    case "brightness":
        var p = try kb.readProfile()
        p.setBrightness(level(args.first), for: p.effectID)
        try kb.writeProfile(p)

    case "speed":
        var p = try kb.readProfile()
        p.setSpeed(level(args.first), for: p.effectID)
        try kb.writeProfile(p)

    case "color":
        var p = try kb.readProfile()
        var pal = try kb.readPalette()
        pal.setColor(color(args.first), for: p.effectID)
        try kb.writePalette(pal)
        p.setMulticolor(false, for: p.effectID)
        try kb.writeProfile(p)

    case "key-color":
        let c = color(args.first)
        let names = args.dropFirst()
        var colors = try kb.readKeyColors()
        if names.isEmpty {
            colors = KeyColors(fill: c)
        } else {
            for n in names { colors[findKey(n).index] = c }
        }
        try kb.writeKeyColors(colors)
        var p = try kb.readProfile()
        p.effectID = Effect.custom.id
        try kb.writeProfile(p)

    case "sleep":
        guard let v = args.first else { fail(usage) }
        var p = try kb.readProfile()
        if v == "off" {
            p.sleepSeconds = 0
        } else if let s = Int(v), s >= 30, s <= 255 * 30 {
            p.sleepSeconds = s
        } else {
            fail("Sleep must be `off` or 30–7650 seconds.")
        }
        try kb.writeProfile(p)

    case "remap":
        guard args.count == 2 else { fail(usage) }
        let key = findKey(args[0])
        guard let named = KeyAction.catalog.first(where: { $0.title.caseInsensitiveCompare(args[1]) == .orderedSame }) else {
            fail("Unknown action '\(args[1])'. Run `k673ctl actions`.")
        }
        var m = try kb.readKeyMatrix()
        m[key.index] = named.action
        try kb.writeKeyMatrix(m)

    case "remap-reset":
        let factory = KeyMatrix.factory
        var m = factory
        if let name = args.first {
            let key = findKey(name)
            m = try kb.readKeyMatrix()
            m[key.index] = factory[key.index]
        }
        try kb.writeKeyMatrix(m)

    case "backup":
        guard let path = args.first else { fail(usage) }
        try Backup.capture(from: kb).save(to: URL(fileURLWithPath: path))

    case "restore":
        guard let path = args.first else { fail(usage) }
        try Backup.load(from: URL(fileURLWithPath: path)).restore(to: kb)

    default:
        fail(usage)
    }
    kb.close()
} catch {
    fail("Error: \(error.localizedDescription)")
}
