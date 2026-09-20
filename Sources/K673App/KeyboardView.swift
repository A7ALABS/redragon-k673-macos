import K673Kit
import SwiftUI

struct KeyboardView: View {
    var led: (KeyDef) -> Color?
    var caption: (KeyDef) -> String = { $0.label }
    var selected: Set<Int> = []
    var marked: Set<Int> = []
    /// Report every key the pointer crosses during a drag (painting) instead of only the first one.
    var continuous = false
    var onKey: ((KeyDef) -> Void)?

    @State private var lastHit: Int?

    private static let keys = Layout.keys + [Layout.knob]
    private static let origin = CGPoint(x: 18, y: 14)
    private static let size = CGSize(width: 626, height: 250)

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / Self.size.width
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14 * scale)
                    .fill(LinearGradient(colors: [Color(white: 0.13), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 14 * scale).stroke(Color.white.opacity(0.1)))
                ForEach(Self.keys) { key in
                    Keycap(key: key, led: led(key), caption: caption(key),
                           isSelected: selected.contains(key.index), isMarked: marked.contains(key.index), scale: scale)
                        .frame(width: key.w * scale, height: key.h * scale)
                        .offset(x: (key.x - Self.origin.x) * scale, y: (key.y - Self.origin.y) * scale)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    guard let key = hit(g.location, scale), key.index != lastHit else { return }
                    if lastHit == nil || continuous { onKey?(key) }
                    lastHit = key.index
                }
                .onEnded { _ in lastHit = nil })
        }
        .aspectRatio(Self.size.width / Self.size.height, contentMode: .fit)
    }

    private func hit(_ p: CGPoint, _ scale: Double) -> KeyDef? {
        let x = p.x / scale + Self.origin.x, y = p.y / scale + Self.origin.y
        return Self.keys.first { x >= $0.x && x <= $0.x + $0.w && y >= $0.y && y <= $0.y + $0.h }
    }
}

private struct Keycap: View {
    let key: KeyDef
    let led: Color?
    let caption: String
    let isSelected: Bool
    let isMarked: Bool
    let scale: Double

    var body: some View {
        let shape = key.index == Layout.knobIndex ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 5 * scale))
        ZStack {
            shape
                .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.15)], startPoint: .top, endPoint: .bottom))
                .shadow(color: led?.opacity(0.75) ?? .clear, radius: 5 * scale)
            shape.stroke(border, lineWidth: isSelected ? 2 : 1)
            Text(caption)
                .font(.system(size: 9.5 * scale, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 2)
                .foregroundStyle(led ?? Color(white: 0.45))
                .shadow(color: led ?? .clear, radius: 3 * scale)
        }
    }

    private var border: Color {
        if isSelected { return .white }
        return isMarked ? Theme.accent : Color.white.opacity(0.08)
    }
}
