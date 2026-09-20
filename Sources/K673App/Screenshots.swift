import AppKit
import K673Kit
import SwiftUI

/// `K673App --screenshots <dir>` renders the README images from demo data, so no keyboard or screen-recording permission is needed.
@MainActor
enum Screenshots {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--screenshots"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSApplication.shared.setActivationPolicy(.accessory)

        let shots: [(String, String, Page, UInt8, Bool)] = [
            ("lighting", "Redragon", .lighting, 6, true),
            ("lighting-single", "Midnight", .lighting, 2, false),
            ("per-key", "Synthwave", .perKey, Effect.custom.id, true),
            ("keys", "Emerald", .keys, 3, true),
            ("device", "Graphite", .device, 3, true),
            ("device-light", "Snow", .device, 3, true),
        ]
        for (name, theme, page, effect, multicolor) in shots {
            UserDefaults.standard.set(theme, forKey: Theme.storageKey)
            let view = RootView(initialPage: page).environmentObject(demoModel(effect: effect, multicolor: multicolor))
            save(view, size: CGSize(width: 1100, height: 760), to: dir.appendingPathComponent("\(name).png"))
        }
        UserDefaults.standard.set("Redragon", forKey: Theme.storageKey)
        save(MenuBarPanel().environmentObject(demoModel(effect: 7, multicolor: true)), size: nil, to: dir.appendingPathComponent("menu-bar.png"))
        UserDefaults.standard.removeObject(forKey: Theme.storageKey)
        exit(0)
    }

    private static func demoModel(effect: UInt8, multicolor: Bool) -> AppModel {
        let model = AppModel(attachKnob: false)
        var profile = try! Profile(bytes: [UInt8](repeating: 0, count: Profile.length))
        profile.effectID = effect
        profile.sleepSeconds = 180
        for e in Effect.all {
            profile.setBrightness(Profile.maxLevel, for: e.id)
            profile.setSpeed(3, for: e.id)
            profile.setMulticolor(multicolor, for: e.id)
        }
        var palette = try! Palette(bytes: [UInt8](repeating: 0, count: Palette.length))
        for e in Effect.all { palette.setColor(RGB(0, 170, 255), for: e.id) }
        var colors = KeyColors(fill: RGB(40, 0, 160))
        for name in ["W", "A", "S", "D", "Up", "Down", "Left", "Right"] {
            if let k = Layout.keys.first(where: { $0.name == name }) { colors[k.index] = RGB(255, 40, 120) }
        }
        for k in Layout.keys where k.y < 40 { colors[k.index] = RGB(0, 220, 255) }
        colors[Layout.knobIndex] = RGB(255, 200, 0)
        var matrix = KeyMatrix.factory
        if let caps = Layout.keys.first(where: { $0.name == "CapsLock" }) { matrix[caps.index] = .key(0, modifiers: 0x01) }
        if let ins = Layout.keys.first(where: { $0.name == "Insert" }) { matrix[ins.index] = .consumer(0xcd) }
        model.loadDemo(profile: profile, palette: palette, keyColors: colors, matrix: matrix)
        return model
    }

    private static func save(_ view: some View, size: CGSize?, to url: URL) {
        let host = NSHostingView(rootView: view)
        let size = size ?? host.fittingSize
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20000, y: -20000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        // Lets ScrollView content, pickers and the first TimelineView frame settle before capturing.
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: url)
        window.close()
    }
}
