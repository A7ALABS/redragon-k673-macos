import Foundation
import K673Kit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Connection: Equatable {
        case connecting
        case connected(firmware: String)
        case failed(String)
    }

    @Published var connection: Connection = .connecting
    @Published var profile: Profile?
    @Published var palette: Palette?
    @Published var keyColors: KeyColors?
    @Published var matrix: KeyMatrix?
    @Published var busy = false
    @Published var lastError: String?
    @Published private(set) var knobMode = KnobMode(rawValue: UserDefaults.standard.string(forKey: "knobMode") ?? "") ?? .volume
    @Published private(set) var knobNeedsAccessibility = false

    private var kb: Keyboard?
    private let queue = DispatchQueue(label: "k673.device")
    private var pending: [String: DispatchWorkItem] = [:]
    private let knob = KnobController()

    init(attachKnob: Bool = true) {
        guard attachKnob else { return }
        knob.onTurn = { [weak self] clockwise in
            MainActor.assumeIsolated { self?.knobTurned(clockwise) }
        }
        setKnobMode(knobMode)
    }

    func loadDemo(profile: Profile, palette: Palette, keyColors: KeyColors, matrix: KeyMatrix) {
        self.profile = profile
        self.palette = palette
        self.keyColors = keyColors
        self.matrix = matrix
        connection = .connected(firmware: "1000")
    }

    func setKnobMode(_ mode: KnobMode) {
        knobMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "knobMode")
        knob.setSuppressVolume(mode != .volume)
        knobNeedsAccessibility = knob.tapState == .needsAccessibility
        if mode == .volume { remap(Layout.knobIndex, to: .mute) }
    }

    private func knobTurned(_ clockwise: Bool) {
        // Without the tap the volume key still reaches macOS, so acting as well would do both.
        guard knob.tapState == .active else { return }
        switch knobMode {
        case .volume:
            break
        case .screenBrightness:
            KnobController.postScreenBrightness(up: clockwise)
        case .backlight:
            updateProfile { p in
                let id = p.effectID
                let level = Int(p.brightness(for: id)) + (clockwise ? 1 : -1)
                p.setBrightness(UInt8(max(0, min(Int(Profile.maxLevel), level))), for: id)
            }
        }
    }

    func connect() {
        connection = .connecting
        kb?.close()
        let kb = Keyboard()
        self.kb = kb
        run { [weak self] in
            do {
                try kb.open()
                guard try kb.isKeyboardOnline() else { throw K673Error.keyboardOffline }
                let info = try kb.info()
                let profile = try kb.readProfile()
                let palette = try kb.readPalette()
                let colors = try kb.readKeyColors()
                let matrix = try kb.readKeyMatrix()
                self?.onMain {
                    self?.profile = profile
                    self?.palette = palette
                    self?.keyColors = colors
                    self?.matrix = matrix
                    self?.connection = .connected(firmware: info.firmware)
                }
            } catch {
                self?.onMain { self?.connection = .failed(error.localizedDescription) }
            }
        }
    }

    private func run(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }

    private nonisolated func onMain(_ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated(body) }
    }

    /// Coalesces bursts from sliders and the color picker; each full write is 10–30 radio packets.
    private func schedule(_ key: String, _ op: @escaping (Keyboard) throws -> Void) {
        pending[key]?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, let kb = self.kb else { return }
            self.pending[key] = nil
            self.busy = true
            self.run {
                do {
                    try op(kb)
                    self.onMain { self.busy = false }
                } catch {
                    self.onMain {
                        self.busy = false
                        self.lastError = error.localizedDescription
                    }
                }
            }
        }
        pending[key] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    /// `force` writes even when the cached profile already matches: the effect can be changed from the keyboard itself
    /// (Fn + Ins, knob click), so the cache is not proof of what the keyboard is showing.
    func updateProfile(force: Bool = false, _ change: (inout Profile) -> Void) {
        guard var p = profile else { return }
        change(&p)
        guard force || p != profile else { return }
        profile = p
        schedule("profile") { try $0.writeProfile(p) }
    }

    /// Picks up effect changes made on the keyboard while the app was in the background.
    func refreshProfile() {
        guard let kb, case .connected = connection, !busy, pending.isEmpty else { return }
        run { [weak self] in
            guard let fresh = try? kb.readProfile() else { return }
            self?.onMain {
                guard let self, !self.busy else { return }
                self.profile = fresh
            }
        }
    }

    func setColor(_ c: RGB, for effect: UInt8) {
        guard var pal = palette, pal.color(for: effect) != c else { return }
        pal.setColor(c, for: effect)
        palette = pal
        schedule("palette") { try $0.writePalette(pal) }
        updateProfile { $0.setMulticolor(false, for: effect) }
    }

    func paint(_ indices: [Int], _ c: RGB) {
        guard var colors = keyColors else { return }
        for i in indices { colors[i] = c }
        keyColors = colors
        schedule("colors") { try $0.writeKeyColors(colors) }
        updateProfile(force: true) { p in
            p.effectID = Effect.custom.id
            // Painting onto a keyboard whose custom brightness was turned to 0 (Fn + ↓) would otherwise look like nothing happened.
            if p.brightness(for: Effect.custom.id) == 0 { p.setBrightness(Profile.maxLevel, for: Effect.custom.id) }
        }
    }

    func remap(_ index: Int, to action: KeyAction) {
        guard var m = matrix, m[index] != action else { return }
        m[index] = action
        matrix = m
        schedule("matrix") { try $0.writeKeyMatrix(m) }
    }

    func resetKeymap() {
        let m = KeyMatrix.factory
        matrix = m
        schedule("matrix") { try $0.writeKeyMatrix(m) }
    }

    func backup(to url: URL) {
        guard let kb else { return }
        busy = true
        run { [weak self] in
            let result = Result { try Backup.capture(from: kb).save(to: url) }
            self?.onMain {
                self?.busy = false
                if case .failure(let e) = result { self?.lastError = e.localizedDescription }
            }
        }
    }

    func restore(from url: URL) {
        guard let kb else { return }
        busy = true
        run { [weak self] in
            let result = Result { try Backup.load(from: url).restore(to: kb) }
            self?.onMain {
                self?.busy = false
                if case .failure(let e) = result { self?.lastError = e.localizedDescription }
                self?.connect()
            }
        }
    }
}

extension RGB {
    var color: Color { Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }

    init(_ color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(UInt8(round(c.redComponent * 255)), UInt8(round(c.greenComponent * 255)), UInt8(round(c.blueComponent * 255)))
    }
}
