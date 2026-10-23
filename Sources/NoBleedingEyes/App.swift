import SwiftUI

@main
struct NoBleedingEyesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var engine = Engine.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(engine)
                .environmentObject(engine.prefs)
                .environmentObject(engine.location)
        } label: {
            Image(systemName: engine.isDark ? "moon.stars.fill" : "sun.max.fill")
        }
        .menuBarExtraStyle(.window)

        Window("Réglages", id: SettingsView.windowID) {
            SettingsView()
                .environmentObject(engine)
                .environmentObject(engine.prefs)
                .environmentObject(engine.location)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            MainActor.assumeIsolated { Snapshotter.run(into: URL(fileURLWithPath: arguments[index + 1])) }
            exit(0)
        }
        #endif
        Task { @MainActor in Engine.shared.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { Engine.shared.shutdown() }
    }
}
