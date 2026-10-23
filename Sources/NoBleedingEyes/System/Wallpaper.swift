import AppKit

enum Wallpaper {
    /// Sets the image on every display. macOS only exposes the current Space of each display.
    static func apply(path: String) {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return }
        let url = URL(fileURLWithPath: path)
        let workspace = NSWorkspace.shared
        for screen in NSScreen.screens where workspace.desktopImageURL(for: screen) != url {
            let options = workspace.desktopImageOptions(for: screen) ?? [:]
            try? workspace.setDesktopImageURL(url, for: screen, options: options)
        }
    }

    static var current: String? {
        guard let screen = NSScreen.main else { return nil }
        return NSWorkspace.shared.desktopImageURL(for: screen)?.path
    }
}
