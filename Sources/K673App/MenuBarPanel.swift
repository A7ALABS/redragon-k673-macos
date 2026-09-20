import K673Kit
import SwiftUI

struct MenuBarPanel: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Theme.storageKey) private var themeName = ThemePalette.all[0].name
    @AppStorage("lastEffect") private var lastEffect = Int(Effect.all[0].id)

    private static let presets = ["FF0000", "FF7A00", "FFE600", "00FF00", "0000FF", "00E5FF", "FF00FF", "FFFFFF"].compactMap(RGB.init(hex:))

    var body: some View {
        let _ = Theme.current = Theme.named(themeName)
        VStack(alignment: .leading, spacing: 14) {
            header
            if let profile = model.profile, let palette = model.palette {
                controls(profile, palette)
            } else {
                Text(statusMessage).font(.system(size: 12)).foregroundStyle(Theme.dim)
                GhostButton(title: "Retry", icon: "arrow.clockwise") { model.connect() }
            }
            section("Knob") {
                HStack(spacing: 6) {
                    ForEach(KnobMode.allCases) { mode in
                        Chip(title: mode.short, active: model.knobMode == mode) { model.setKnobMode(mode) }
                    }
                }
            }
            HStack {
                GhostButton(title: "Open K673 Control", icon: "macwindow") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                GhostButton(title: "Quit", destructive: true) { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(Theme.current.isDark ? .dark : .light)
        .id(themeName)
        .onAppear { model.refreshProfile() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("K673RGB-PRO").font(.system(size: 14, weight: .heavy))
            Spacer()
            if model.busy { ProgressView().controlSize(.mini) }
            Circle().fill(isConnected ? Color.green : Theme.accent).frame(width: 8, height: 8)
        }
    }

    private var isConnected: Bool {
        if case .connected = model.connection { return true }
        return false
    }

    private var statusMessage: String {
        if case .failed(let message) = model.connection { return message }
        return "Connecting…"
    }

    @ViewBuilder
    private func controls(_ profile: Profile, _ palette: Palette) -> some View {
        let id = profile.effectID
        let effect = Effect.byID(id)
        let lit = id != Effect.off.id
        HStack(spacing: 10) {
            Button {
                if lit {
                    lastEffect = Int(id)
                    model.updateProfile { $0.effectID = Effect.off.id }
                } else {
                    model.updateProfile { $0.effectID = UInt8(lastEffect) }
                }
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(lit ? Theme.accent : Theme.raised))
                    .foregroundStyle(lit ? Theme.onAccent : Theme.dim)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(lit ? "Turn lighting off" : "Turn lighting back on")

            Picker("", selection: Binding(get: { id }, set: { v in model.updateProfile(force: true) { $0.effectID = v } })) {
                ForEach(Effect.all) { Text($0.name).tag($0.id) }
                if effect == nil { Text("Effect \(id)").tag(id) }
            }
            .labelsHidden()
        }
        if lit {
            section("Brightness") {
                TrackSlider(value: Binding(get: { Double(profile.brightness(for: id)) },
                                           set: { v in model.updateProfile { $0.setBrightness(UInt8(v), for: id) } }),
                            range: 0...Double(Profile.maxLevel))
            }
        }
        if effect?.hasSpeed == true {
            section("Speed") {
                TrackSlider(value: Binding(get: { Double(profile.speed(for: id)) },
                                           set: { v in model.updateProfile { $0.setSpeed(UInt8(v), for: id) } }),
                            range: 0...Double(Profile.maxLevel))
            }
        }
        if effect?.hasColor == true {
            section("Color") {
                HStack(spacing: 6) {
                    ForEach(Self.presets, id: \.self) { c in
                        Swatch(color: c, active: !profile.isMulticolor(for: id) && palette.color(for: id) == c) { model.setColor(c, for: id) }
                    }
                    Button { model.updateProfile { $0.setMulticolor(true, for: id) } } label: {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(profile.isMulticolor(for: id) ? Theme.text : Theme.text.opacity(0.15),
                                                                              lineWidth: profile.isMulticolor(for: id) ? 2 : 1))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Colourful")
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 10, weight: .bold)).kerning(1.2).foregroundStyle(Theme.dim)
            content()
        }
    }
}

extension KnobMode {
    var short: String {
        switch self {
        case .volume: return "Volume"
        case .screenBrightness: return "Screen"
        case .backlight: return "Backlight"
        }
    }
}
