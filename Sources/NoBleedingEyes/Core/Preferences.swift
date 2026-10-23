import Foundation

enum ScheduleMode: String, CaseIterable, Identifiable {
    case solar
    case custom
    case ambient
    case manual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .solar: return "Lever et coucher du soleil"
        case .custom: return "Horaires fixes"
        case .ambient: return "Luminosité ambiante (Home Assistant)"
        case .manual: return "Manuel"
        }
    }
}

enum WarmthStart: String, CaseIterable, Identifiable {
    case sunset
    case customTime
    case always

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sunset: return "Au coucher du soleil"
        case .customTime: return "À heure fixe"
        case .always: return "Toute la journée"
        }
    }
}

enum WarmthRenderer: String, CaseIterable, Identifiable {
    case gamma
    case overlay

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gamma: return "Standard (gamma)"
        case .overlay: return "Compatibilité (filtre)"
        }
    }
}

/// User settings, persisted in `UserDefaults` on every change.
@MainActor
final class Preferences: ObservableObject {
    private let defaults: UserDefaults

    // Appearance schedule
    @Published var scheduleMode: ScheduleMode { didSet { defaults.set(scheduleMode.rawValue, forKey: "scheduleMode") } }
    /// Minutes added to sunrise / sunset, in -120...120.
    @Published var sunriseOffset: Int { didSet { defaults.set(sunriseOffset, forKey: "sunriseOffset") } }
    @Published var sunsetOffset: Int { didSet { defaults.set(sunsetOffset, forKey: "sunsetOffset") } }
    /// Minutes since midnight, used by `.custom` and as fallback without a location.
    @Published var lightTime: Int { didSet { defaults.set(lightTime, forKey: "lightTime") } }
    @Published var darkTime: Int { didSet { defaults.set(darkTime, forKey: "darkTime") } }

    // Location
    @Published var useManualLocation: Bool { didSet { defaults.set(useManualLocation, forKey: "useManualLocation") } }
    @Published var manualLatitude: Double { didSet { defaults.set(manualLatitude, forKey: "manualLatitude") } }
    @Published var manualLongitude: Double { didSet { defaults.set(manualLongitude, forKey: "manualLongitude") } }

    // Weather
    @Published var weatherEnabled: Bool { didSet { defaults.set(weatherEnabled, forKey: "weatherEnabled") } }
    /// Mean daytime cloud cover (%) from which the day is considered dark.
    @Published var cloudThreshold: Double { didSet { defaults.set(cloudThreshold, forKey: "cloudThreshold") } }
    @Published var useFahrenheit: Bool { didSet { defaults.set(useFahrenheit, forKey: "useFahrenheit") } }

    // Wallpapers
    @Published var lightWallpaper: String { didSet { defaults.set(lightWallpaper, forKey: "lightWallpaper") } }
    @Published var darkWallpaper: String { didSet { defaults.set(darkWallpaper, forKey: "darkWallpaper") } }

    // Evening warmth
    @Published var warmthEnabled: Bool { didSet { defaults.set(warmthEnabled, forKey: "warmthEnabled") } }
    @Published var warmthStart: WarmthStart { didSet { defaults.set(warmthStart.rawValue, forKey: "warmthStart") } }
    @Published var warmthStartTime: Int { didSet { defaults.set(warmthStartTime, forKey: "warmthStartTime") } }
    @Published var warmthKelvin: Double { didSet { defaults.set(warmthKelvin, forKey: "warmthKelvin") } }
    /// Duration of the fade in and fade out, in minutes.
    @Published var warmthTransition: Int { didSet { defaults.set(warmthTransition, forKey: "warmthTransition") } }
    @Published var warmthRenderer: WarmthRenderer { didSet { defaults.set(warmthRenderer.rawValue, forKey: "warmthRenderer") } }
    @Published var suspendNightShift: Bool { didSet { defaults.set(suspendNightShift, forKey: "suspendNightShift") } }

    // Home Assistant illuminance sensor
    @Published var haURL: String { didSet { defaults.set(haURL, forKey: "haURL") } }
    @Published var haEntityID: String { didSet { defaults.set(haEntityID, forKey: "haEntityID") } }
    /// Long-lived access token, kept in the Keychain.
    @Published var haToken: String { didSet { Keychain.write(haToken, account: "homeAssistantToken") } }
    /// Hysteresis: dark below `luxDarkBelow`, light above `luxLightAbove`, unchanged in between.
    @Published var luxDarkBelow: Double { didSet { defaults.set(luxDarkBelow, forKey: "luxDarkBelow") } }
    @Published var luxLightAbove: Double { didSet { defaults.set(luxLightAbove, forKey: "luxLightAbove") } }
    /// Minutes a reading must stay past a threshold before switching.
    @Published var luxHoldMinutes: Int { didSet { defaults.set(luxHoldMinutes, forKey: "luxHoldMinutes") } }

    // Shortcuts
    @Published var hotkeysEnabled: Bool { didSet { defaults.set(hotkeysEnabled, forKey: "hotkeysEnabled") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        scheduleMode = ScheduleMode(rawValue: defaults.string(forKey: "scheduleMode") ?? "") ?? .solar
        sunriseOffset = Self.value(defaults, "sunriseOffset", 0)
        sunsetOffset = Self.value(defaults, "sunsetOffset", 0)
        lightTime = Self.value(defaults, "lightTime", 7 * 60)
        darkTime = Self.value(defaults, "darkTime", 19 * 60)
        useManualLocation = Self.value(defaults, "useManualLocation", false)
        manualLatitude = Self.value(defaults, "manualLatitude", 48.8566)
        manualLongitude = Self.value(defaults, "manualLongitude", 2.3522)
        weatherEnabled = Self.value(defaults, "weatherEnabled", false)
        cloudThreshold = Self.value(defaults, "cloudThreshold", 85.0)
        useFahrenheit = Self.value(defaults, "useFahrenheit", false)
        lightWallpaper = Self.value(defaults, "lightWallpaper", "")
        darkWallpaper = Self.value(defaults, "darkWallpaper", "")
        warmthEnabled = Self.value(defaults, "warmthEnabled", false)
        warmthStart = WarmthStart(rawValue: defaults.string(forKey: "warmthStart") ?? "") ?? .sunset
        warmthStartTime = Self.value(defaults, "warmthStartTime", 21 * 60)
        warmthKelvin = Self.value(defaults, "warmthKelvin", 3400.0)
        warmthTransition = Self.value(defaults, "warmthTransition", 30)
        warmthRenderer = WarmthRenderer(rawValue: defaults.string(forKey: "warmthRenderer") ?? "") ?? .gamma
        suspendNightShift = Self.value(defaults, "suspendNightShift", true)
        haURL = Self.value(defaults, "haURL", "http://homeassistant.local:8123")
        haEntityID = Self.value(defaults, "haEntityID", "")
        haToken = Keychain.read("homeAssistantToken") ?? ""
        luxDarkBelow = Self.value(defaults, "luxDarkBelow", 30.0)
        luxLightAbove = Self.value(defaults, "luxLightAbove", 80.0)
        luxHoldMinutes = Self.value(defaults, "luxHoldMinutes", 2)
        hotkeysEnabled = Self.value(defaults, "hotkeysEnabled", true)
    }

    private static func value<T>(_ defaults: UserDefaults, _ key: String, _ fallback: T) -> T {
        defaults.object(forKey: key) as? T ?? fallback
    }
}
