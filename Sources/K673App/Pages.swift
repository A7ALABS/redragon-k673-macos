import K673Kit
import SwiftUI
import UniformTypeIdentifiers

struct LightingPage: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let profile = model.profile, let palette = model.palette {
            let id = profile.effectID
            let effect = Effect.byID(id)
            HStack(alignment: .top, spacing: 16) {
                EffectList(current: id) { v in model.updateProfile(force: true) { $0.effectID = v } }
                    .frame(width: 190)
                VStack(spacing: 16) {
                    LightingPreview(profile: profile, palette: palette, keyColors: model.keyColors)
                    Card(title: effect?.name ?? "Effect \(id)") {
                        HStack(alignment: .top, spacing: 22) {
                            VStack(alignment: .leading, spacing: 14) {
                                level("Brightness", profile.brightness(for: id), enabled: id != Effect.off.id) { v in
                                    model.updateProfile { $0.setBrightness(v, for: id) }
                                }
                                level("Speed", profile.speed(for: id), enabled: effect?.hasSpeed == true) { v in
                                    model.updateProfile { $0.setSpeed(v, for: id) }
                                }
                                Toggle("Colourful", isOn: Binding(get: { profile.isMulticolor(for: id) },
                                                                  set: { v in model.updateProfile { $0.setMulticolor(v, for: id) } }))
                                    .toggleStyle(.switch)
                                    .tint(Theme.accent)
                                    .disabled(effect?.hasColor != true)
                                    .opacity(effect?.hasColor == true ? 1 : 0.35)
                            }
                            .frame(width: 170)

                            let colorEnabled = effect?.hasColor == true && !profile.isMulticolor(for: id)
                            ColorPanel(color: palette.color(for: id)) { model.setColor($0, for: id) }
                                .opacity(colorEnabled ? 1 : 0.3)
                                .allowsHitTesting(colorEnabled)
                        }
                    }
                }
            }
        }
    }

    private func level(_ title: String, _ value: UInt8, enabled: Bool, set: @escaping (UInt8) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(value)").font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.dim)
            }
            TrackSlider(value: Binding(get: { Double(value) }, set: { set(UInt8($0)) }), range: 0...Double(Profile.maxLevel))
        }
        .opacity(enabled ? 1 : 0.35)
        .allowsHitTesting(enabled)
    }
}

private struct EffectList: View {
    let current: UInt8
    let select: (UInt8) -> Void

    var body: some View {
        Card(title: "Light effect") {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Effect.all) { e in
                        Button { select(e.id) } label: {
                            HStack {
                                Text(e.name).font(.system(size: 12.5, weight: e.id == current ? .semibold : .regular))
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 27)
                            .background(RoundedRectangle(cornerRadius: 6).fill(e.id == current ? Theme.accent : Color.clear))
                            .foregroundStyle(e.id == current ? Theme.onAccent : Theme.text.opacity(0.75))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Exact for steady/custom/off; animated effects are simulated, and reactive ones also respond to clicks on the preview.
private struct LightingPreview: View {
    let profile: Profile
    let palette: Palette
    let keyColors: KeyColors?

    @State private var taps: [EffectSimulator.Tap] = []

    var body: some View {
        let id = profile.effectID
        let effect = Effect.byID(id)
        let level = 0.35 + 0.65 * Double(profile.brightness(for: id)) / Double(Profile.maxLevel)
        if id == Effect.off.id || effect == nil {
            KeyboardView(led: { _ in nil })
        } else if id == Effect.custom.id {
            KeyboardView(led: { key in
                guard let c = keyColors?[key.index], c != .black else { return nil }
                return c.color.opacity(level)
            })
        } else {
            let single = effect?.hasColor == true && !profile.isMulticolor(for: id)
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let sim = EffectSimulator(effect: id, base: single ? palette.color(for: id) : nil,
                                          speed: Double(profile.speed(for: id)), level: level, taps: taps)
                KeyboardView(led: { sim.color($0, now) }, onKey: { key in
                    taps = taps.suffix(7) + [EffectSimulator.Tap(key: key, at: Date().timeIntervalSinceReferenceDate)]
                })
            }
        }
    }
}

struct PerKeyPage: View {
    @EnvironmentObject var model: AppModel
    @State private var brush = RGB(255, 0, 0)
    @State private var erasing = false

    var body: some View {
        if let colors = model.keyColors {
            VStack(spacing: 16) {
                KeyboardView(led: { colors[$0.index] == .black ? nil : colors[$0.index].color }, continuous: true) { key in
                    model.paint([key.index], erasing ? .black : brush)
                }
                Card(title: "Brush") {
                    HStack(alignment: .top, spacing: 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Chip(title: "Paint", active: !erasing) { erasing = false }
                                Chip(title: "Erase", active: erasing) { erasing = true }
                            }
                            GhostButton(title: "Fill all", icon: "paintbrush.fill") {
                                model.paint(Array(0..<KeyColors.slots), brush)
                            }
                            GhostButton(title: "Clear all", icon: "trash", destructive: true) {
                                model.paint(Array(0..<KeyColors.slots), .black)
                            }
                            Text("Click or drag across keys. Painting switches the keyboard to Custom mode.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(width: 170, alignment: .leading)
                        ColorPanel(color: brush) { brush = $0; erasing = false }
                    }
                }
            }
        }
    }
}

struct KeysPage: View {
    @EnvironmentObject var model: AppModel
    @State private var selection: KeyDef?
    @State private var group = "Letters"
    @State private var confirmReset = false

    private static let groups: [String] = KeyAction.catalog.reduce(into: []) { if !$0.contains($1.group) { $0.append($1.group) } }

    var body: some View {
        if let matrix = model.matrix {
            let factory = KeyMatrix.factory
            let changed = Set((Layout.keys + [Layout.knob]).map(\.index).filter { matrix[$0] != factory[$0] })
            VStack(spacing: 16) {
                KeyboardView(
                    led: { changed.contains($0.index) ? Theme.accent : Color(white: 0.8) },
                    caption: { changed.contains($0.index) ? matrix[$0.index].title : ($0.index == Layout.knobIndex ? "●" : $0.label) },
                    selected: selection.map { [$0.index] } ?? [],
                    marked: changed
                ) { selection = $0 }

                Card(title: "Assignment") {
                    if let key = selection {
                        editor(key, current: matrix[key.index], original: factory[key.index])
                    } else {
                        Text("Select a key to remap it. Remapped keys are shown in red.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                    }
                    HStack {
                        Spacer()
                        GhostButton(title: "Reset all keys…", icon: "arrow.counterclockwise", destructive: true) { confirmReset = true }
                            .opacity(changed.isEmpty ? 0.35 : 1)
                            .disabled(changed.isEmpty)
                    }
                }
            }
            .confirmationDialog("Reset every key to the factory mapping?", isPresented: $confirmReset) {
                Button("Reset all keys", role: .destructive) { model.resetKeymap() }
            }
        }
    }

    @ViewBuilder
    private func editor(_ key: KeyDef, current: KeyAction, original: KeyAction) -> some View {
        HStack(spacing: 10) {
            Text(key.name).font(.system(size: 15, weight: .bold))
            Image(systemName: "arrow.right").foregroundStyle(Theme.dim)
            Text(current.title).font(.system(size: 15, weight: .bold)).foregroundStyle(current == original ? Theme.text : Theme.accent)
            Spacer()
            if current != original {
                GhostButton(title: "Reset key", icon: "arrow.uturn.backward") { model.remap(key.index, to: original) }
            }
        }
        if current.isFn {
            Text("Fn is locked so the Fn layer stays reachable.").font(.system(size: 12)).foregroundStyle(Theme.dim)
        } else {
            HStack(spacing: 6) {
                ForEach(Self.groups, id: \.self) { g in Chip(title: g, active: g == group) { group = g } }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(KeyAction.catalog.filter { $0.group == group }) { item in
                    Chip(title: item.title, active: item.action == current) { model.remap(key.index, to: item.action) }
                }
            }
        }
    }
}

struct ThemeTile: View {
    let palette: ThemePalette
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(palette.background)
                    .overlay(alignment: .bottomLeading) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3).fill(palette.panel).frame(width: 26, height: 16)
                            RoundedRectangle(cornerRadius: 3).fill(palette.raised).frame(width: 16, height: 16)
                            RoundedRectangle(cornerRadius: 3).fill(palette.accent).frame(width: 16, height: 16)
                        }
                        .padding(7)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? Theme.accent : Theme.stroke, lineWidth: active ? 2 : 1))
                    .frame(width: 92, height: 54)
                Text(palette.name)
                    .font(.system(size: 11, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? Theme.text : Theme.dim)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct DevicePage: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Theme.storageKey) private var themeName = ThemePalette.all[0].name
    private let sleepChoices = [0, 60, 120, 180, 300, 600, 900, 1800, 3600]

    var body: some View {
        if let profile = model.profile {
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    Card(title: "Keyboard") {
                        row("Model", "Redragon K673 PRO")
                        row("Connection", "2.4G receiver")
                        if case .connected(let fw) = model.connection { row("Firmware", fw) }
                    }
                    Card(title: "Backup") {
                        Text("Lighting, per-key colors and the key map in one file.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                        HStack {
                            GhostButton(title: "Save backup…", icon: "square.and.arrow.down") { save() }
                            GhostButton(title: "Restore…", icon: "square.and.arrow.up") { open() }
                        }
                    }
                }
                Card(title: "Knob") {
                    HStack(spacing: 6) {
                        Text("Turn").font(.system(size: 12, weight: .medium)).frame(width: 40, alignment: .leading)
                        ForEach(KnobMode.allCases) { mode in
                            Chip(title: mode.rawValue, active: model.knobMode == mode) { model.setKnobMode(mode) }
                        }
                    }
                    if let matrix = model.matrix {
                        let click = matrix[Layout.knobIndex]
                        let factory = KeyMatrix.factory[Layout.knobIndex]
                        HStack(spacing: 6) {
                            Text("Click").font(.system(size: 12, weight: .medium)).frame(width: 40, alignment: .leading)
                            Chip(title: "Mute", active: click == .mute) { model.remap(Layout.knobIndex, to: .mute) }
                            Chip(title: "Play / Pause", active: click == .playPause) { model.remap(Layout.knobIndex, to: .playPause) }
                            Chip(title: "Next lighting effect", active: click == factory) { model.remap(Layout.knobIndex, to: factory) }
                            if ![.mute, .playPause, factory].contains(click) { Chip(title: click.title, active: true) {} }
                        }
                    }
                    if model.knobNeedsAccessibility {
                        HStack {
                            Text("Needs Accessibility permission to take over the knob's volume keys.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.accent)
                            GhostButton(title: "Open settings", icon: "lock.shield") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                            }
                            GhostButton(title: "Recheck", icon: "arrow.clockwise") { model.setKnobMode(model.knobMode) }
                        }
                    }
                    Text("Choosing Volume also sets the click to Mute; any other click action is on the Keys page. The keyboard itself always sends volume keys when the knob turns; this app converts them, so it has to be running (it stays in the menu bar). If turning the knob dims the keyboard LEDs directly instead, hold the knob down for 3 seconds to put it back in its volume mode.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Card(title: "Backlight sleep") {
                    HStack(spacing: 6) {
                        ForEach(sleepChoices, id: \.self) { s in
                            Chip(title: label(s), active: profile.sleepSeconds == s) { model.updateProfile { $0.sleepSeconds = s } }
                        }
                        if !sleepChoices.contains(profile.sleepSeconds) { Chip(title: label(profile.sleepSeconds), active: true) {} }
                    }
                }
                Card(title: "Theme") {
                    HStack(spacing: 12) {
                        ForEach(ThemePalette.all) { palette in
                            ThemeTile(palette: palette, active: palette.name == themeName) { themeName = palette.name }
                        }
                    }
                }
                Card(title: "Good to know") {
                    Text("Fn + ↑ / ↓ on the keyboard change the same brightness shown here; the app picks the change up when it comes to the front. If the backlight is dark, raise Brightness on the Lighting page or press Fn + ↑.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.dim)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.system(size: 12.5))
    }

    private func label(_ s: Int) -> String {
        if s == 0 { return "Never" }
        return s < 120 ? "\(s) s" : s < 3600 ? "\(s / 60) min" : "\(s / 3600) h"
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "k673-backup.json"
        if panel.runModal() == .OK, let url = panel.url { model.backup(to: url) }
    }

    private func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url { model.restore(from: url) }
    }
}
