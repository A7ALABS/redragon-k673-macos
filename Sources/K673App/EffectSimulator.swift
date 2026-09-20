import K673Kit
import SwiftUI

/// On-screen approximation of the firmware animations, written from their names and behaviour; the keyboard renders the real thing itself.
struct EffectSimulator {
    struct Tap {
        let key: KeyDef
        let at: Double
    }

    let effect: UInt8
    /// nil means the effect is in multicolor mode.
    let base: RGB?
    let speed: Double
    let level: Double
    let taps: [Tap]

    private static let keys = Layout.keys + [Layout.knob]
    private static let center = CGPoint(x: 330, y: 140)
    private static let autoTapInterval = 0.8

    private static let snakeOrder: [Int: Int] = {
        let rows = Dictionary(grouping: Layout.keys) { Int(($0.y / 37).rounded()) }
        var order: [Int: Int] = [:]
        var n = 0
        for (i, row) in rows.keys.sorted().enumerated() {
            let sorted = rows[row]!.sorted { $0.x < $1.x }
            for key in i % 2 == 0 ? sorted : sorted.reversed() {
                order[key.index] = n
                n += 1
            }
        }
        return order
    }()

    private static func hash(_ v: Int) -> Int {
        var x = UInt64(truncatingIfNeeded: v) &* 0x9E37_79B9_7F4A_7C15
        x ^= x >> 29
        x = x &* 0xBF58_476D_1CE4_E5B9
        x ^= x >> 32
        return Int(x & 0x7FFF_FFFF)
    }

    private static func unit(_ v: Int) -> Double { Double(hash(v) % 1000) / 1000 }

    private func paint(_ intensity: Double, hue: Double) -> Color? {
        guard intensity > 0.03 else { return nil }
        let h = hue - hue.rounded(.down)
        let color = base?.color ?? Color(hue: h, saturation: 1, brightness: 1)
        return color.opacity(min(intensity, 1) * level)
    }

    /// Recent presses as (key, age in effect-time): the user's clicks plus a steady trickle of random ones so reactive effects are visible untouched.
    private func presses(_ now: Double, rate: Double) -> [(key: KeyDef, age: Double)] {
        var out = taps.map { ($0.key, (now - $0.at) * rate) }
        let slot = Int(now / Self.autoTapInterval)
        for n in (slot - 5)...slot {
            let key = Self.keys[Self.hash(n) % Self.keys.count]
            out.append((key, (now - Double(n) * Self.autoTapInterval) * rate))
        }
        return out.filter { $0.1 >= 0 && $0.1 < 4 }
    }

    func color(_ key: KeyDef, _ now: Double) -> Color? {
        let rate = 0.35 + 0.3 * speed
        let t = now * rate
        let cx = key.x + key.w / 2, cy = key.y + key.h / 2
        let u = cx / Layout.width, v = (cy - 27) / 230
        let dx = cx - Self.center.x, dy = cy - Self.center.y
        let angle = atan2(dy, dx) / (2 * .pi)
        let dist = hypot(dx, dy) / 330

        switch effect {
        case 1:
            return paint(1, hue: u)
        case 2:
            let breath = (1 - cos(t * 2)) / 2
            return paint(breath, hue: (t / .pi).rounded(.down) * 0.17)
        case 3:
            return paint(1, hue: u - t * 0.4)
        case 4:
            // Flash away: a press shoots light outward along its own row.
            var best = 0.0
            for p in presses(now, rate: rate) where abs(p.key.y - key.y) < 12 {
                let front = p.age * 420
                let gap = abs(abs(cx - (p.key.x + p.key.w / 2)) - front)
                if gap < 40 { best = max(best, (1 - gap / 40) * max(0, 1 - p.age / 1.6)) }
            }
            return paint(best, hue: u)
        case 5:
            let slot = Int((t / 1.2).rounded(.down))
            var best = 0.0, hue = 0.0
            for m in (slot - 1)...slot {
                let seed = key.index * 7919 + m
                guard Self.hash(seed) % 100 < 16 else { continue }
                let age = t - (Double(m) + Self.unit(seed + 1)) * 1.2
                if age >= 0, age < 1.2, 1 - age / 1.2 > best { best = 1 - age / 1.2; hue = Self.unit(seed + 2) }
            }
            return paint(best, hue: hue)
        case 6:
            return paint(1, hue: angle - t * 0.35)
        case 7:
            var best = 0.0, hue = 0.0
            for p in presses(now, rate: rate) {
                let d = hypot(cx - (p.key.x + p.key.w / 2), cy - (p.key.y + p.key.h / 2))
                let gap = abs(d - p.age * 260)
                let i = (1 - gap / 34) * max(0, 1 - p.age / 2.2)
                if gap < 34, i > best { best = i; hue = Self.unit(p.key.index) }
            }
            return paint(best, hue: hue)
        case 8:
            let phase = Self.unit(key.index * 31)
            let s = sin(t * (1.2 + phase) + phase * 2 * .pi)
            return paint(max(0, s) * max(0, s), hue: phase + (t * 0.1).rounded(.down) * 0.13)
        case 9:
            var best = 0.0
            for p in presses(now, rate: rate) where p.key.index == key.index { best = max(best, 1 - p.age / 2.5) }
            return paint(best, hue: Self.unit(key.index))
        case 10:
            guard let pos = Self.snakeOrder[key.index] else { return nil }
            let count = Self.snakeOrder.count
            let head = Int(t * 14) % count
            let behind = (head - pos + count) % count
            return paint(behind < 9 ? 1 - Double(behind) / 9 : 0, hue: Double(pos) / Double(count))
        case 11:
            return paint(1, hue: t * 0.12 + u * 0.15)
        case 12:
            var best = 0.0
            for p in presses(now, rate: rate) {
                let d = hypot(cx - (p.key.x + p.key.w / 2), cy - (p.key.y + p.key.h / 2))
                if d < 60 { best = max(best, (1 - d / 60) * max(0, 1 - p.age / 0.9)) }
            }
            return paint(best, hue: Self.unit(key.index))
        case 13:
            let wave = 0.5 + 0.42 * sin(2 * .pi * (u * 1.4 - t * 0.35))
            return paint(1 - abs(v - wave) / 0.22, hue: u - t * 0.2)
        case 14:
            let sweep = (1 - cos(t * 1.1)) / 2
            return paint(1 - abs(u - sweep) / 0.09, hue: sweep)
        case 15:
            let blade = sin(2 * .pi * (3 * angle - t * 0.45))
            return paint(max(0, blade), hue: angle - t * 0.45)
        case 16:
            return paint(1, hue: v * 0.8 - t * 0.4)
        case 17:
            return paint(1, hue: dist * 0.9 - t * 0.4)
        case 18:
            let arm = sin(2 * .pi * (2 * angle + dist * 1.4 - t * 0.5))
            return paint(0.15 + 0.85 * max(0, arm), hue: angle + dist - t * 0.5)
        default:
            return nil
        }
    }
}
