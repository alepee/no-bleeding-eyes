import AppKit

/// Reads and switches the system-wide light/dark appearance.
enum SystemAppearance {
    static var isDark: Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let style = CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication) as? String
        return style == "Dark"
    }

    /// Uses SkyLight when available (no permission prompt), falls back to System Events.
    /// Returns false when the switch failed, typically because Automation access was refused.
    @discardableResult
    static func setDark(_ dark: Bool) -> Bool {
        if let setTheme = skyLightSetTheme {
            setTheme(dark)
            if waitUntil(dark: dark) { return true }
        }
        return setWithAppleScript(dark)
    }

    private typealias SetThemeFunction = @convention(c) (Bool) -> Void

    private static let skyLightSetTheme: SetThemeFunction? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let symbol = dlsym(handle, "SLSSetAppearanceThemeLegacy") else { return nil }
        return unsafeBitCast(symbol, to: SetThemeFunction.self)
    }()

    private static func waitUntil(dark: Bool) -> Bool {
        for _ in 0..<10 {
            if isDark == dark { return true }
            usleep(50_000)
        }
        return false
    }

    private static func setWithAppleScript(_ dark: Bool) -> Bool {
        let source = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }
}
