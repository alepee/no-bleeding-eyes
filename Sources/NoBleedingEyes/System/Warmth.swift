import AppKit
import CoreGraphics

enum ColorTemperature {
    static let neutral: Double = 6500
    static let range: ClosedRange<Double> = 1900...6500

    /// RGB multipliers for a blackbody at `kelvin`, normalised to 1 at 6500K (Tanner Helland's fit).
    static func multipliers(_ kelvin: Double) -> (red: Double, green: Double, blue: Double) {
        let raw = rgb(kelvin)
        let white = rgb(neutral)
        return (min(raw.r / white.r, 1), min(raw.g / white.g, 1), min(raw.b / white.b, 1))
    }

    private static func rgb(_ kelvin: Double) -> (r: Double, g: Double, b: Double) {
        let t = kelvin / 100
        let r = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
        let g = t <= 66 ? 99.4708025861 * log(t) - 161.1195681661 : 288.1221695283 * pow(t - 60, -0.0755148492)
        let b = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307)
        func unit(_ value: Double) -> Double { min(max(value / 255, 0), 1) }
        return (unit(r), unit(g), unit(b))
    }
}

/// Warms the screen by scaling each display's gamma table, like f.lux.
@MainActor
final class GammaWarmth {
    private struct Table {
        let red: [CGGammaValue]
        let green: [CGGammaValue]
        let blue: [CGGammaValue]
    }

    private var originals: [CGDirectDisplayID: Table] = [:]
    private var isApplied = false

    func apply(kelvin: Double) {
        let tint = ColorTemperature.multipliers(kelvin)
        for display in Self.onlineDisplays() {
            guard let base = originals[display] ?? capture(display) else { continue }
            originals[display] = base
            let red = base.red.map { $0 * CGGammaValue(tint.red) }
            let green = base.green.map { $0 * CGGammaValue(tint.green) }
            let blue = base.blue.map { $0 * CGGammaValue(tint.blue) }
            CGSetDisplayTransferByTable(display, UInt32(red.count), red, green, blue)
        }
        isApplied = true
    }

    func reset() {
        guard isApplied else { return }
        CGDisplayRestoreColorSyncSettings()
        originals.removeAll()
        isApplied = false
    }

    /// Displays were added or reconfigured: recapture their calibrated tables on next apply.
    func displaysChanged() {
        if isApplied { CGDisplayRestoreColorSyncSettings() }
        originals.removeAll()
    }

    private func capture(_ display: CGDirectDisplayID) -> Table? {
        let capacity = CGDisplayGammaTableCapacity(display)
        guard capacity > 0 else { return nil }
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = red
        var blue = red
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, capacity, &red, &green, &blue, &count) == .success, count > 0 else { return nil }
        let size = Int(count)
        return Table(red: Array(red.prefix(size)), green: Array(green.prefix(size)), blue: Array(blue.prefix(size)))
    }

    private static func onlineDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &displays, &count)
        return Array(displays.prefix(Int(count)))
    }
}

/// Fallback for displays that ignore gamma tables: a click-through amber layer above every window.
@MainActor
final class OverlayWarmth {
    private var windows: [NSWindow] = []

    func apply(kelvin: Double) {
        let screens = NSScreen.screens
        if windows.map(\.frame) != screens.map(\.frame) {
            hide()
            windows = screens.map(makeWindow)
        }
        let strength = (ColorTemperature.neutral - kelvin) / (ColorTemperature.neutral - ColorTemperature.range.lowerBound)
        let color = NSColor(srgbRed: 1, green: 0.55, blue: 0.1, alpha: 0.4 * max(0, min(strength, 1)))
        for window in windows {
            window.backgroundColor = color
            window.orderFrontRegardless()
        }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.setFrame(screen.frame, display: false)
        return window
    }
}

/// Night Shift control through the private CoreBrightness client, so both filters never stack.
enum NightShift {
    private static let client: NSObject? = {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
              let type = NSClassFromString("CBBlueLightClient") as? NSObject.Type else { return nil }
        return type.init()
    }()

    /// Whether Night Shift is currently on, or nil when it cannot be read.
    static var isOn: Bool? {
        let selector = NSSelectorFromString("getBlueLightStatus:")
        guard let client, client.responds(to: selector) else { return nil }
        typealias GetStatus = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
        let getStatus = unsafeBitCast(client.method(for: selector), to: GetStatus.self)
        // Status struct: { BOOL active; BOOL enabled; BOOL sunSchedulePermitted; int mode; ... }, well under 64 bytes.
        let status = UnsafeMutableRawPointer.allocate(byteCount: 64, alignment: 8)
        defer { status.deallocate() }
        status.initializeMemory(as: UInt8.self, repeating: 0, count: 64)
        guard getStatus(client, selector, status) else { return nil }
        return status.load(fromByteOffset: 1, as: Bool.self)
    }

    static func setOn(_ on: Bool) {
        let selector = NSSelectorFromString("setEnabled:")
        guard let client, client.responds(to: selector) else { return }
        typealias SetEnabled = @convention(c) (AnyObject, Selector, Bool) -> Bool
        _ = unsafeBitCast(client.method(for: selector), to: SetEnabled.self)(client, selector, on)
    }
}
