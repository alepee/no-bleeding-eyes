import AppKit
import Carbon
import Combine
import CoreLocation

enum HomeAssistantConnection: Equatable {
    case unknown
    case checking
    case connected(String)
    case failed(String)
}

/// Decides, every tick, which appearance, wallpaper and colour temperature the Mac should have, and applies them.
@MainActor
final class Engine: ObservableObject {
    static let shared = Engine()

    struct Transition {
        let date: Date
        let toDark: Bool
    }

    @Published private(set) var isDark = SystemAppearance.isDark
    @Published private(set) var sunTimes: SunTimes?
    @Published private(set) var nextTransition: Transition?
    @Published private(set) var weather: WeatherReport?
    @Published private(set) var weatherForcesDark = false
    @Published private(set) var currentKelvin = ColorTemperature.neutral
    /// Next time evening warmth starts fading in, when it is currently off.
    @Published private(set) var nextWarmthStart: Date?
    @Published private(set) var appearanceError: String?
    @Published private(set) var ambientLux: Double?
    @Published private(set) var ambientError: String?
    @Published private(set) var ambientSensors: [HomeAssistantClient.Sensor] = []
    @Published private(set) var sensorListError: String?
    @Published private(set) var haConnection = HomeAssistantConnection.unknown

    let prefs: Preferences
    let location = LocationProvider()

    private let calendar = Calendar.current
    private let weatherService = WeatherService()
    private let gamma = GammaWarmth()
    private let overlay = OverlayWarmth()

    private var lastAppliedDark: Bool?

    private var warmthOverride: Bool?
    private var warmthOverrideBaseline = false
    private var nightShiftSuspended = false

    /// First forecast of the day: the weather decision is taken once, so the screen never flickers.
    private var dayForecast: WeatherReport?
    private var weatherFetchInFlight = false
    private var lastWeatherAttempt: Date?

    /// Debounced lux decision; nil until a reading falls outside the hysteresis band.
    private var ambientDark: Bool?
    private var ambientCandidate: (dark: Bool, since: Date)?
    private var lastLuxAttempt: Date?
    private var lastLuxSuccess: Date?
    private var luxFetchInFlight = false

    private var appliedWallpaper: String?
    private var timer: Timer?
    private var subscriptions = Set<AnyCancellable>()

    private init(prefs: Preferences? = nil) {
        self.prefs = prefs ?? Preferences()
    }

    #if DEBUG
    /// Engine filled with sample data and throwaway preferences, for UI snapshots.
    static func preview() -> Engine {
        let suite = "com.alepee.NoBleedingEyes.preview"
        UserDefaults().removePersistentDomain(forName: suite)
        let engine = Engine(prefs: Preferences(defaults: UserDefaults(suiteName: suite)!))
        let prefs = engine.prefs
        prefs.weatherEnabled = true
        prefs.warmthEnabled = true
        prefs.haURL = "https://home.example.org"
        prefs.haEntityID = "sensor.salon_illuminance"

        let now = Date()
        let calendar = Calendar.current
        engine.isDark = false
        engine.sunTimes = SunTimes(sunrise: calendar.date(on: now, minutes: 8 * 60 + 22), sunset: calendar.date(on: now, minutes: 18 * 60 + 47))
        engine.nextTransition = Transition(date: calendar.date(on: now, minutes: 18 * 60 + 47), toDark: true)
        engine.weather = WeatherReport(
            temperature: 12.6, cloudCover: 100, precipitation: 0.4, uvIndex: 1, weatherCode: 61,
            hourly: [], coordinate: CLLocationCoordinate2D(latitude: 48.85, longitude: 2.35), fetchedAt: now
        )
        engine.weatherForcesDark = true
        engine.currentKelvin = 4200
        engine.lastAppliedDark = false
        engine.ambientLux = 142
        engine.haConnection = .connected("Maison · Home Assistant 2026.10.2")
        engine.ambientSensors = [
            HomeAssistantClient.Sensor(id: "sensor.salon_illuminance", name: "Salon", lux: 142),
            HomeAssistantClient.Sensor(id: "sensor.bureau_illuminance", name: "Bureau", lux: 310),
        ]
        return engine
    }
    #endif

    // MARK: - Lifecycle

    func start() {
        // Clears a tint left behind by a previous crash.
        CGDisplayRestoreColorSyncSettings()

        if !prefs.useManualLocation { location.refresh() }

        prefs.objectWillChange
            .merge(with: location.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.tick() }
            .store(in: &subscriptions)

        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.prefs.useManualLocation { self.location.refresh() }
                self.gamma.displaysChanged()
                self.tick()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.gamma.displaysChanged()
                self?.appliedWallpaper = nil
                self?.tick()
            }
        }

        tick()
    }

    func shutdown() {
        timer?.invalidate()
        gamma.reset()
        overlay.hide()
        if nightShiftSuspended { NightShift.setOn(true) }
        HotKeyCenter.shared.unregisterAll()
    }

    // MARK: - User actions

    func setAppearance(_ choice: AppearanceChoice) {
        prefs.appearanceChoice = choice
        tick()
    }

    func toggleAppearance() {
        setAppearance(SystemAppearance.isDark ? .light : .dark)
    }

    func toggleWarmth() {
        warmthOverride = currentKelvin >= ColorTemperature.neutral - 1
        warmthOverrideBaseline = scheduledWarmthFactor(at: Date()) > 0
        tick()
    }

    // MARK: - Tick

    var coordinate: CLLocationCoordinate2D? {
        prefs.useManualLocation
            ? CLLocationCoordinate2D(latitude: prefs.manualLatitude, longitude: prefs.manualLongitude)
            : location.coordinate
    }

    func tick() {
        let now = Date()
        sunTimes = coordinate.flatMap { SolarCalculator.sunTimes(on: now, coordinate: $0, calendar: calendar) }

        if !prefs.useManualLocation, let last = location.lastUpdate, now.timeIntervalSince(last) > 6 * 3600 {
            location.refresh()
        }

        updateWeatherIfNeeded(now: now)
        updateAmbientIfNeeded(now: now)
        updateAppearance(now: now)
        updateWallpaper()
        updateWarmth(now: now)
        updateHotKeys()
    }

    // MARK: - Appearance

    /// Start of light and dark mode on the day containing `day`.
    private func boundaries(on day: Date) -> (light: Date, dark: Date) {
        if prefs.scheduleMode != .custom, let coordinate,
           let sun = SolarCalculator.sunTimes(on: day, coordinate: coordinate, calendar: calendar) {
            return (sun.sunrise.addingTimeInterval(Double(prefs.sunriseOffset) * 60),
                    sun.sunset.addingTimeInterval(Double(prefs.sunsetOffset) * 60))
        }
        return (calendar.date(on: day, minutes: prefs.lightTime), calendar.date(on: day, minutes: prefs.darkTime))
    }

    /// Appearance the schedule asks for, or nil in manual mode.
    private func scheduledDark(at now: Date) -> Bool? {
        guard prefs.scheduleMode != .manual else { return nil }
        if prefs.scheduleMode == .ambient, isAmbientLive(at: now), let ambientDark { return ambientDark }
        let today = boundaries(on: now)
        let isDaytime = now >= today.light && now < today.dark
        return !isDaytime || weatherForcesDark
    }

    private func updateAppearance(now: Date) {
        weatherForcesDark = {
            guard prefs.weatherEnabled, let dayForecast else { return false }
            let today = boundaries(on: now)
            return dayForecast.isDarkDay(from: today.light, to: today.dark, cloudThreshold: prefs.cloudThreshold)
        }()

        let scheduled = scheduledDark(at: now)
        let systemDark = SystemAppearance.isDark

        // A change made outside the app (System Settings, Control Centre) away from the schedule pins that appearance.
        if let lastAppliedDark, systemDark != lastAppliedDark, prefs.appearanceChoice == .auto,
           let scheduled, systemDark != scheduled {
            prefs.appearanceChoice = systemDark ? .dark : .light
        }

        let pinned: Bool? = switch prefs.appearanceChoice {
        case .light: false
        case .dark: true
        case .auto: nil
        }
        let desired = pinned ?? scheduled ?? systemDark
        if desired != systemDark {
            applyAppearance(desired)
        }
        lastAppliedDark = SystemAppearance.isDark
        isDark = lastAppliedDark ?? desired
        nextTransition = computeNextTransition(after: now)
    }

    private func applyAppearance(_ dark: Bool) {
        if SystemAppearance.setDark(dark) {
            appearanceError = nil
        } else {
            appearanceError = "Impossible de changer l'apparence : autorisez l'app à contrôler « System Events » dans Réglages Système › Confidentialité › Automatisation."
        }
    }

    private func computeNextTransition(after now: Date) -> Transition? {
        guard prefs.scheduleMode != .manual, prefs.appearanceChoice == .auto else { return nil }
        if prefs.scheduleMode == .ambient, isAmbientLive(at: now), ambientDark != nil { return nil }
        let candidates = (0...1).flatMap { offset -> [Transition] in
            let day = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            let bounds = boundaries(on: day)
            return [Transition(date: bounds.light, toDark: false), Transition(date: bounds.dark, toDark: true)]
        }
        return candidates.filter { $0.date > now }.min { $0.date < $1.date }
    }

    // MARK: - Wallpaper

    private func updateWallpaper() {
        let path = isDark ? prefs.darkWallpaper : prefs.lightWallpaper
        guard path != appliedWallpaper else { return }
        Wallpaper.apply(path: path)
        appliedWallpaper = path
    }

    // MARK: - Weather

    private func updateWeatherIfNeeded(now: Date) {
        guard prefs.weatherEnabled, let coordinate else {
            weather = nil
            dayForecast = nil
            return
        }
        guard !weatherFetchInFlight else { return }

        let movedFar = weather.map {
            abs($0.coordinate.latitude - coordinate.latitude) > 0.05 || abs($0.coordinate.longitude - coordinate.longitude) > 0.05
        } ?? true
        let dayForecastIsToday = dayForecast.map { calendar.isDate($0.fetchedAt, inSameDayAs: now) } ?? false
        let isFresh = weather.map { now.timeIntervalSince($0.fetchedAt) < 30 * 60 } ?? false
        guard movedFar || !dayForecastIsToday || !isFresh else { return }
        if let lastWeatherAttempt, now.timeIntervalSince(lastWeatherAttempt) < 5 * 60, !movedFar { return }

        weatherFetchInFlight = true
        lastWeatherAttempt = now
        Task {
            defer { weatherFetchInFlight = false }
            guard let report = try? await weatherService.fetch(at: coordinate) else { return }
            weather = report
            if movedFar || !dayForecastIsToday { dayForecast = report }
            tick()
        }
    }

    // MARK: - Ambient light (Home Assistant)

    private func homeAssistant() throws -> HomeAssistantClient {
        try HomeAssistantClient(baseURL: prefs.haURL, token: prefs.haToken)
    }

    /// Validates URL and token, then loads the sensor list.
    func testHomeAssistant() async {
        haConnection = .checking
        do {
            let info = try await homeAssistant().serverInfo()
            haConnection = .connected("\(info.name) · Home Assistant \(info.version)")
            await loadAmbientSensors()
        } catch {
            haConnection = .failed(error.localizedDescription)
            ambientSensors = []
        }
    }

    func resetHomeAssistantStatus() {
        haConnection = .unknown
    }

    /// A sensor silent for 10 minutes hands control back to the sun.
    private func isAmbientLive(at now: Date) -> Bool {
        lastLuxSuccess.map { now.timeIntervalSince($0) < 10 * 60 } ?? false
    }

    private func updateAmbientIfNeeded(now: Date) {
        guard prefs.scheduleMode == .ambient else {
            ambientDark = nil
            ambientCandidate = nil
            return
        }
        if let lastLuxAttempt, now.timeIntervalSince(lastLuxAttempt) < 30 { return }
        Task { await refreshAmbient() }
    }

    /// Polls the configured sensor once; also used by the "Lire" button.
    func refreshAmbient() async {
        guard !luxFetchInFlight else { return }
        guard !prefs.haEntityID.isEmpty else {
            ambientLux = nil
            ambientError = "Aucun capteur choisi."
            return
        }
        luxFetchInFlight = true
        lastLuxAttempt = Date()
        defer { luxFetchInFlight = false }
        do {
            let lux = try await homeAssistant().illuminance(of: prefs.haEntityID)
            ambientLux = lux
            ambientError = nil
            lastLuxSuccess = Date()
            evaluateAmbient(lux: lux, now: Date())
        } catch {
            ambientError = error.localizedDescription
        }
        tick()
    }

    func loadAmbientSensors() async {
        do {
            ambientSensors = try await homeAssistant().illuminanceSensors()
            sensorListError = ambientSensors.isEmpty
                ? "Aucun capteur de luminosité sur ce serveur (classe « illuminance » ou unité « lx »)."
                : nil
        } catch {
            sensorListError = error.localizedDescription
        }
    }

    private func evaluateAmbient(lux: Double, now: Date) {
        let target: Bool? = lux < prefs.luxDarkBelow ? true : (lux > prefs.luxLightAbove ? false : nil)
        guard let target, target != ambientDark else {
            ambientCandidate = nil
            return
        }
        guard ambientDark != nil else {
            ambientDark = target
            return
        }
        if let candidate = ambientCandidate, candidate.dark == target {
            if now.timeIntervalSince(candidate.since) >= Double(prefs.luxHoldMinutes) * 60 {
                ambientDark = target
                ambientCandidate = nil
            }
        } else {
            ambientCandidate = (target, now)
        }
    }

    // MARK: - Warmth

    private func sunrise(on day: Date) -> Date {
        if let coordinate, let sun = SolarCalculator.sunTimes(on: day, coordinate: coordinate, calendar: calendar) {
            return sun.sunrise
        }
        return calendar.date(on: day, minutes: prefs.lightTime)
    }

    private func warmthStart(on day: Date) -> Date {
        if prefs.warmthStart == .customTime {
            return calendar.date(on: day, minutes: prefs.warmthStartTime)
        }
        if let coordinate, let sun = SolarCalculator.sunTimes(on: day, coordinate: coordinate, calendar: calendar) {
            return sun.sunset
        }
        return calendar.date(on: day, minutes: prefs.darkTime)
    }

    /// 0 = neutral, 1 = full warmth. Fades in from the start time and out after sunrise.
    private func scheduledWarmthFactor(at now: Date) -> Double {
        guard prefs.warmthEnabled else { return 0 }
        if prefs.warmthStart == .always { return 1 }
        let fade = Double(max(prefs.warmthTransition, 1)) * 60

        return (-1...0).map { offset -> Double in
            let day = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            var start = warmthStart(on: day)
            // A start time after midnight belongs to the following night.
            if start < sunrise(on: day).addingTimeInterval(fade) {
                start = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            }
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let end = sunrise(on: nextDay).addingTimeInterval(fade)
            guard now >= start, now < end else { return 0 }
            return min(1, now.timeIntervalSince(start) / fade, end.timeIntervalSince(now) / fade)
        }.max() ?? 0
    }

    private func updateWarmth(now: Date) {
        let factor = scheduledWarmthFactor(at: now)
        nextWarmthStart = {
            guard prefs.warmthEnabled, prefs.warmthStart != .always, factor == 0 else { return nil }
            let today = warmthStart(on: now)
            return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)
        }()
        if warmthOverride != nil, (factor > 0) != warmthOverrideBaseline {
            warmthOverride = nil
        }
        let effectiveFactor = warmthOverride.map { $0 ? 1 : 0 } ?? factor
        let kelvin = ColorTemperature.neutral - effectiveFactor * (ColorTemperature.neutral - prefs.warmthKelvin)
        currentKelvin = kelvin.rounded()

        let isActive = kelvin < ColorTemperature.neutral - 1
        handOverNightShift(warmthActive: isActive, now: now)

        switch (prefs.warmthRenderer, isActive) {
        case (.gamma, true):
            overlay.hide()
            gamma.apply(kelvin: kelvin)
        case (.overlay, true):
            gamma.reset()
            overlay.apply(kelvin: kelvin)
        case (_, false):
            gamma.reset()
            overlay.hide()
        }
    }

    private func handOverNightShift(warmthActive: Bool, now: Date) {
        if warmthActive, prefs.suspendNightShift, !nightShiftSuspended, NightShift.isOn == true {
            NightShift.setOn(false)
            nightShiftSuspended = true
        } else if !warmthActive, nightShiftSuspended {
            // Give Night Shift back only at night; its own schedule would have turned it off by day.
            let today = boundaries(on: now)
            if now < sunrise(on: now) || now >= today.dark { NightShift.setOn(true) }
            nightShiftSuspended = false
        }
    }

    // MARK: - Shortcuts

    private func updateHotKeys() {
        let center = HotKeyCenter.shared
        guard prefs.hotkeysEnabled == center.isEmpty else { return }
        center.unregisterAll()
        guard prefs.hotkeysEnabled else { return }
        let modifiers = controlKey | optionKey | cmdKey
        center.register(keyCode: kVK_ANSI_D, modifiers: modifiers) { [weak self] in self?.toggleAppearance() }
        center.register(keyCode: kVK_ANSI_W, modifiers: modifiers) { [weak self] in self?.toggleWarmth() }
    }
}
