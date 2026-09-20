import K673Kit
import SwiftUI

struct ColorWheel: View {
    let color: RGB
    let pick: (RGB) -> Void

    private static let hues = (0...36).map { Color(hue: Double($0) / 36, saturation: 1, brightness: 1) }

    var body: some View {
        GeometryReader { geo in
            let radius = min(geo.size.width, geo.size.height) / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let hsb = color.hsb
            ZStack {
                Circle().fill(AngularGradient(colors: Self.hues, center: .center))
                Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: radius))
                Circle().stroke(Theme.text.opacity(0.15))
                Circle()
                    .fill(color.color)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .frame(width: 14, height: 14)
                    .position(x: center.x + cos(hsb.h * 2 * .pi) * hsb.s * radius,
                              y: center.y + sin(hsb.h * 2 * .pi) * hsb.s * radius)
            }
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let dx = g.location.x - center.x, dy = g.location.y - center.y
                var h = atan2(dy, dx) / (2 * .pi)
                if h < 0 { h += 1 }
                // LEDs have no use for a darkened hue; overall level is the brightness slider's job.
                pick(RGB(h: h, s: min(hypot(dx, dy) / radius, 1), b: 1))
            })
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct Swatch: View {
    let color: RGB
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 5)
                .fill(color.color)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(active ? Theme.text : Theme.text.opacity(0.15), lineWidth: active ? 2 : 1))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
    }
}

struct ColorPanel: View {
    let color: RGB
    let pick: (RGB) -> Void

    @AppStorage("customColors") private var stored = ""
    @State private var hexDraft = ""
    @FocusState private var hexFocused: Bool

    private static let presets = ["FF0000", "FF7A00", "FFE600", "00FF00", "0000FF", "00E5FF", "FF00FF", "FFFFFF"].compactMap(RGB.init(hex:))
    private static let customSlots = 8
    private static let swatchColumns = Array(repeating: GridItem(.fixed(24), spacing: 6), count: 4)

    private var custom: [RGB] { stored.split(separator: ",").compactMap { RGB(hex: String($0)) } }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            ColorWheel(color: color, pick: pick).frame(width: 124, height: 124)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 5).fill(color.color).frame(width: 24, height: 24)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.stroke))
                    TextField("#RRGGBB", text: $hexDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .frame(width: 96, height: 24)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.raised))
                        .focused($hexFocused)
                        .onSubmit { if let c = RGB(hex: hexDraft) { pick(c) } else { hexDraft = color.hex } }
                }
                channel("R", \.r, .red)
                channel("G", \.g, .green)
                channel("B", \.b, Color(red: 0.25, green: 0.45, blue: 1))
            }
            .frame(minWidth: 150, maxWidth: 260)

            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: Self.swatchColumns, alignment: .leading, spacing: 6) {
                    ForEach(Self.presets, id: \.self) { c in Swatch(color: c, active: c == color) { pick(c) } }
                }
                Text("CUSTOM").font(.system(size: 10, weight: .bold)).kerning(1.2).foregroundStyle(Theme.dim)
                LazyVGrid(columns: Self.swatchColumns, alignment: .leading, spacing: 6) {
                    ForEach(custom, id: \.self) { c in
                        Swatch(color: c, active: c == color) { pick(c) }
                            .contextMenu { Button("Remove") { save(custom.filter { $0 != c }) } }
                    }
                    if custom.count < Self.customSlots, !custom.contains(color) {
                        Button { save(custom + [color]) } label: {
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Theme.text.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3]))
                                .overlay(Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.dim))
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Save the current color")
                    }
                }
            }
            .frame(width: 4 * 24 + 3 * 6, alignment: .leading)
        }
        .onAppear { hexDraft = color.hex }
        .onChange(of: color) { c in if !hexFocused { hexDraft = c.hex } }
    }

    private func channel(_ name: String, _ path: WritableKeyPath<RGB, UInt8>, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(name).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.dim).frame(width: 10)
            TrackSlider(value: Binding(get: { Double(color[keyPath: path]) },
                                       set: { v in var c = color; c[keyPath: path] = UInt8(v); pick(c) }),
                        range: 0...255, tint: tint)
            Text("\(color[keyPath: path])")
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 28, alignment: .trailing)
        }
    }

    private func save(_ colors: [RGB]) {
        stored = colors.map { String($0.hex.dropFirst()) }.joined(separator: ",")
    }
}
