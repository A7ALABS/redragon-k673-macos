import K673Kit
import SwiftUI

struct ThemePalette: Identifiable, Equatable {
    let name: String
    let background, rail, panel, raised, accent, text, onAccent: Color
    let isDark: Bool

    var id: String { name }

    private static func hex(_ v: UInt32) -> Color {
        Color(.sRGB, red: Double(v >> 16 & 0xff) / 255, green: Double(v >> 8 & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }

    private init(_ name: String, bg: UInt32, rail: UInt32, panel: UInt32, raised: UInt32, accent: UInt32,
                 text: UInt32 = 0xffffff, onAccent: UInt32 = 0xffffff, isDark: Bool = true) {
        self.name = name
        background = Self.hex(bg); self.rail = Self.hex(rail); self.panel = Self.hex(panel); self.raised = Self.hex(raised)
        self.accent = Self.hex(accent); self.text = Self.hex(text); self.onAccent = Self.hex(onAccent)
        self.isDark = isDark
    }

    static let all: [ThemePalette] = [
        ThemePalette("Redragon", bg: 0x0f0f12, rail: 0x0a0a0d, panel: 0x1a1a1f, raised: 0x26262e, accent: 0xe3172b),
        ThemePalette("Midnight", bg: 0x0b1020, rail: 0x070b17, panel: 0x121a30, raised: 0x1b2745, accent: 0x4c8dff),
        ThemePalette("Synthwave", bg: 0x140a24, rail: 0x0e0619, panel: 0x1e1136, raised: 0x2c1a4d, accent: 0xff3fb4),
        ThemePalette("Emerald", bg: 0x08110c, rail: 0x050b08, panel: 0x0f1c14, raised: 0x172a1e, accent: 0x2ee686, onAccent: 0x04120a),
        ThemePalette("Amber", bg: 0x12100b, rail: 0x0c0a07, panel: 0x1d1a12, raised: 0x2a2519, accent: 0xffb020, onAccent: 0x1a1200),
        ThemePalette("Graphite", bg: 0x1c1c1e, rail: 0x141416, panel: 0x2c2c2e, raised: 0x3a3a3c, accent: 0x0a84ff),
        ThemePalette("Snow", bg: 0xf2f3f5, rail: 0xe4e6eb, panel: 0xffffff, raised: 0xeceef2, accent: 0xe3172b, text: 0x15171a, isDark: false),
    ]
}

enum Theme {
    static let storageKey = "theme"
    /// Views read these statics directly, so whoever changes `current` must also rebuild the tree (RootView does it with `.id`).
    static var current = named(UserDefaults.standard.string(forKey: storageKey))

    static func named(_ name: String?) -> ThemePalette { ThemePalette.all.first { $0.name == name } ?? ThemePalette.all[0] }

    static var background: Color { current.background }
    static var rail: Color { current.rail }
    static var panel: Color { current.panel }
    static var raised: Color { current.raised }
    static var accent: Color { current.accent }
    static var text: Color { current.text }
    static var onAccent: Color { current.onAccent }
    static var stroke: Color { current.text.opacity(0.09) }
    static var dim: Color { current.text.opacity(0.55) }
}

struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.2)
                    .foregroundStyle(Theme.dim)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.stroke))
    }
}

struct Chip: View {
    let title: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .frame(minWidth: 34, minHeight: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(active ? Theme.accent : Theme.raised))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.stroke))
                .foregroundStyle(active ? Theme.onAccent : Theme.text.opacity(0.8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct GhostButton: View {
    let title: String
    var icon: String?
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(destructive ? Theme.accent.opacity(0.6) : Theme.stroke))
            .foregroundStyle(destructive ? Theme.accent : Theme.text.opacity(0.9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct TrackSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var tint: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            let span = range.upperBound - range.lowerBound
            let fraction = span == 0 ? 0 : (value - range.lowerBound) / span
            let knob = 14.0
            let usable = geo.size.width - knob
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.text.opacity(0.14)).frame(height: 4)
                Capsule().fill(tint).frame(width: knob / 2 + usable * fraction, height: 4)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.black.opacity(0.15)))
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .frame(width: knob, height: knob)
                    .offset(x: usable * fraction)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let f = min(max((g.location.x - knob / 2) / usable, 0), 1)
                let raw = range.lowerBound + f * span
                value = (raw / step).rounded() * step
            })
        }
        .frame(height: 20)
    }
}

extension RGB {
    var hsb: (h: Double, s: Double, b: Double) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(self.b) / 255, alpha: 1)
            .getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (Double(h), Double(s), Double(b))
    }

    init(h: Double, s: Double, b: Double) {
        self.init(Color(hue: h, saturation: s, brightness: b))
    }
}
