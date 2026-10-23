#if DEBUG
import SwiftUI

/// Renders the main views to PNG, in light and dark, without touching the running system.
/// Usage: NoBleedingEyes --snapshot <directory>
@MainActor
enum Snapshotter {
    static func run(into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let engine = Engine.preview()
        let views: [(name: String, view: AnyView, size: CGSize?)] = [("menu", AnyView(MenuContentView()), nil)]
            + SettingsPane.allCases.map { ("settings-\($0.rawValue)", AnyView(SettingsView(pane: $0)), nil) }
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for entry in views {
                let root = entry.view
                    .environmentObject(engine)
                    .environmentObject(engine.prefs)
                    .environmentObject(engine.location)
                    .background(Color(nsColor: .windowBackgroundColor))
                render(root, size: entry.size, appearance: appearance, to: directory.appendingPathComponent("\(entry.name)-\(suffix).png"))
            }
        }
    }

    private static func render<V: View>(_ view: V, size: CGSize?, appearance: NSAppearance.Name, to url: URL) {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: appearance)
        host.frame = CGRect(origin: .zero, size: size ?? host.fittingSize)

        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        host.display()

        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        }
        window.orderOut(nil)
    }
}
#endif
