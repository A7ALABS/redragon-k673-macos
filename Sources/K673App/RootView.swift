import K673Kit
import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case lighting = "Lighting"
    case perKey = "Per-key"
    case keys = "Keys"
    case device = "Device"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .lighting: return "lightbulb.fill"
        case .perKey: return "paintpalette.fill"
        case .keys: return "keyboard.fill"
        case .device: return "slider.horizontal.3"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var page: Page
    @AppStorage(Theme.storageKey) private var themeName = ThemePalette.all[0].name

    init(initialPage: Page = .lighting) { _page = State(initialValue: initialPage) }

    var body: some View {
        let _ = Theme.current = Theme.named(themeName)
        HStack(spacing: 0) {
            rail
            VStack(spacing: 0) {
                header
                content.padding([.horizontal, .bottom], 20)
            }
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .frame(minWidth: 1040, minHeight: 700)
        .preferredColorScheme(Theme.current.isDark ? .dark : .light)
        .id(themeName)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshProfile() }
        .alert("Keyboard error", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.lastError ?? "")
        }
    }

    private var rail: some View {
        VStack(spacing: 6) {
            Image(systemName: "keyboard")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.accent)
                .padding(.top, 38)
                .padding(.bottom, 18)
            ForEach(Page.allCases) { p in
                Button { page = p } label: {
                    VStack(spacing: 4) {
                        Image(systemName: p.icon).font(.system(size: 17))
                        Text(p.rawValue).font(.system(size: 9.5, weight: .medium))
                    }
                    .frame(width: 60, height: 52)
                    .background(RoundedRectangle(cornerRadius: 10).fill(page == p ? Theme.accent.opacity(0.18) : Color.clear))
                    .foregroundStyle(page == p ? Theme.accent : Theme.dim)
                    .overlay(alignment: .leading) {
                        if page == p { Capsule().fill(Theme.accent).frame(width: 3, height: 24).offset(x: -6) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(width: 76)
        .background(Theme.rail)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("K673RGB-PRO").font(.system(size: 17, weight: .heavy)).kerning(0.5)
            Text(page.rawValue.uppercased()).font(.system(size: 10, weight: .bold)).kerning(1.2).foregroundStyle(Theme.dim)
            Spacer()
            if model.busy {
                ProgressView().controlSize(.small)
                Text("Writing…").font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
            Circle().fill(statusColor).frame(width: 8, height: 8).shadow(color: statusColor, radius: 4)
            Text(statusText).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
    }

    private var statusColor: Color {
        switch model.connection {
        case .connected: return .green
        case .connecting: return .yellow
        case .failed: return Theme.accent
        }
    }

    private var statusText: String {
        switch model.connection {
        case .connected: return "Connected · 2.4G"
        case .connecting: return "Connecting…"
        case .failed: return "Not connected"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.connection {
        case .connecting:
            ProgressView("Connecting to keyboard…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 14) {
                Image(systemName: "keyboard.badge.ellipsis").font(.system(size: 44)).foregroundStyle(Theme.dim)
                Text(message).multilineTextAlignment(.center).frame(maxWidth: 440)
                HStack {
                    GhostButton(title: "Input Monitoring settings", icon: "lock.shield") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                    }
                    GhostButton(title: "Retry", icon: "arrow.clockwise") { model.connect() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .connected:
            Group {
                switch page {
                case .lighting: LightingPage()
                case .perKey: PerKeyPage()
                case .keys: KeysPage()
                case .device: DevicePage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
