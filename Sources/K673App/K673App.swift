import SwiftUI

@main
struct K673App: App {
    @StateObject private var model = AppModel()

    init() { Screenshots.runIfRequested() }

    var body: some Scene {
        Window("K673 Control", id: "main") {
            RootView()
                .environmentObject(model)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    if case .connected = model.connection {} else { model.connect() }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        MenuBarExtra("K673 Control", systemImage: "keyboard") {
            MenuBarPanel().environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}
