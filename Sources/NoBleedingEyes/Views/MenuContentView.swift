import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var engine: Engine
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var location: LocationProvider
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            status
            appearancePicker
            if let error = engine.appearanceError {
                Notice(text: error, systemImage: "exclamationmark.triangle.fill", color: .red)
            }
            if prefs.scheduleMode == .ambient {
                ambientModule
            }
            if prefs.weatherEnabled {
                weatherModule
            }
            warmthModule
            footer
        }
        .padding(12)
        .frame(width: 320)
    }

    // MARK: - Status

    private var status: some View {
        HStack(spacing: 12) {
            ModeBadge(isDark: engine.isDark, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle).font(.headline)
                Text(statusReason).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    private var statusTitle: String {
        let mode = engine.isDark ? "Sombre" : "Clair"
        guard let next = engine.nextTransition, !engine.isAppearanceOverridden else { return "Mode \(mode.lowercased())" }
        return "\(mode) jusqu'à \(next.date.shortTime)"
    }

    private var statusReason: String {
        if engine.isAppearanceOverridden { return "Forcé manuellement jusqu'au prochain changement" }
        switch prefs.scheduleMode {
        case .manual:
            return "Mode manuel"
        case .custom:
            return "Horaires fixes"
        case .ambient where engine.ambientError == nil && engine.ambientLux != nil:
            return "Luminosité ambiante"
        case .solar, .ambient:
            if engine.weatherForcesDark && engine.isDark { return "Ciel couvert : journée sombre" }
            let place = prefs.useManualLocation ? nil : location.placeName
            let reason = engine.isDark ? "Soleil couché" : "Soleil levé"
            return place.map { "\(reason) à \($0)" } ?? reason
        }
    }

    private var appearancePicker: some View {
        Picker("Apparence", selection: Binding(get: { engine.isDark }, set: { engine.setAppearance(dark: $0) })) {
            Label("Clair", systemImage: "sun.max.fill").tag(false)
            Label("Sombre", systemImage: "moon.fill").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
    }

    // MARK: - Modules

    private var ambientModule: some View {
        Module {
            HStack(spacing: 10) {
                ModuleIcon(systemImage: "light.max", color: .yellow)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Luminosité ambiante").font(.callout.weight(.medium))
                    if let error = engine.ambientError {
                        Text("\(error) Retour au soleil.").font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Sombre sous \(Int(prefs.luxDarkBelow)) lx, clair au-dessus de \(Int(prefs.luxLightAbove)) lx")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if let lux = engine.ambientLux {
                    Text("\(Int(lux.rounded())) lx").font(.title3.weight(.semibold)).monospacedDigit()
                }
            }
        }
    }

    private var weatherModule: some View {
        Module {
            if let weather = engine.weather {
                HStack(spacing: 10) {
                    Image(systemName: WeatherCode.systemImage(weather.weatherCode))
                        .symbolRenderingMode(.multicolor)
                        .font(.title2)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(WeatherCode.label(weather.weatherCode)).font(.callout.weight(.medium))
                        Text("Nuages \(Int(weather.cloudCover)) % · Pluie \(weather.precipitation, specifier: "%.1f") mm · UV \(Int(weather.uvIndex.rounded()))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(formattedTemperature(weather.temperature)).font(.title3.weight(.semibold)).monospacedDigit()
                }
                if engine.weatherForcesDark {
                    Divider()
                    Label("Journée sombre décidée ce matin", systemImage: "cloud.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 10) {
                    ModuleIcon(systemImage: "cloud.sun.fill", color: .cyan)
                    Text("Météo en attente…").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var warmthModule: some View {
        Module {
            HStack(spacing: 10) {
                ModuleIcon(systemImage: "flame.fill", color: .orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Chaleur du soir").font(.callout.weight(.medium))
                    Text(warmthCaption).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Toggle("Chaleur du soir", isOn: $prefs.warmthEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            KelvinSlider(kelvin: $prefs.warmthKelvin)
                .disabled(!prefs.warmthEnabled)
                .opacity(prefs.warmthEnabled ? 1 : 0.5)
        }
    }

    private var warmthCaption: String {
        let target = "\(Int(prefs.warmthKelvin)) K"
        if engine.currentKelvin < ColorTemperature.neutral {
            return engine.currentKelvin > prefs.warmthKelvin ? "Transition : \(Int(engine.currentKelvin)) K → \(target)" : "Active · \(target)"
        }
        guard prefs.warmthEnabled else { return "Désactivée" }
        return engine.nextWarmthStart.map { "Démarre à \($0.shortTime) · \(target)" } ?? target
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                openWindow(id: SettingsView.windowID)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Réglages…", systemImage: "gearshape")
            }
            Spacer()
            Button("Quitter") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private func formattedTemperature(_ celsius: Double) -> String {
        prefs.useFahrenheit ? "\(Int((celsius * 9 / 5 + 32).rounded()))°" : "\(Int(celsius.rounded()))°"
    }
}

// MARK: - Shared components

/// Rounded tile grouping one feature, in the spirit of Control Centre modules.
struct Module<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// White glyph on a coloured rounded square, as in System Settings.
struct ModuleIcon: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
    }
}

struct ModeBadge: View {
    let isDark: Bool
    let size: CGFloat

    var body: some View {
        Image(systemName: isDark ? "moon.stars.fill" : "sun.max.fill")
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: isDark ? [.indigo, .purple] : [.yellow, .orange],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: Circle()
            )
    }
}

/// Continuous slider over the warmth range, with the colour scale underneath.
struct KelvinSlider: View {
    @Binding var kelvin: Double

    var body: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(get: { kelvin }, set: { kelvin = ($0 / 100).rounded() * 100 }),
                in: ColorTemperature.range
            )
            KelvinGradient().frame(height: 4).padding(.horizontal, 2)
            HStack {
                Text("Bougie")
                Spacer()
                Text("\(Int(kelvin)) K").monospacedDigit()
                Spacer()
                Text("Jour")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

struct KelvinGradient: View {
    var body: some View {
        let stops = stride(from: ColorTemperature.range.lowerBound, through: ColorTemperature.range.upperBound, by: 400).map { kelvin in
            let tint = ColorTemperature.multipliers(kelvin)
            return Color(red: tint.red, green: tint.green, blue: tint.blue)
        }
        LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing).clipShape(Capsule())
    }
}

/// Icon and wrapping text, never truncated.
struct Notice: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(color)
        }
        .font(.callout)
    }
}

extension Date {
    var shortTime: String { formatted(date: .omitted, time: .shortened) }
}
