import ServiceManagement
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case schedule
    case weather
    case homeAssistant
    case wallpaper
    case warmth
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule: return "Planning"
        case .weather: return "Météo"
        case .homeAssistant: return "Home Assistant"
        case .wallpaper: return "Fonds d'écran"
        case .warmth: return "Chaleur du soir"
        case .general: return "Général"
        }
    }

    var systemImage: String {
        switch self {
        case .schedule: return "circle.lefthalf.filled"
        case .weather: return "cloud.sun.fill"
        case .homeAssistant: return "house.fill"
        case .wallpaper: return "photo.fill"
        case .warmth: return "flame.fill"
        case .general: return "gearshape.fill"
        }
    }

    var color: Color {
        switch self {
        case .schedule: return .indigo
        case .weather: return .cyan
        case .homeAssistant: return .blue
        case .wallpaper: return .purple
        case .warmth: return .orange
        case .general: return .gray
        }
    }
}

@MainActor
private final class SettingsNavigation: ObservableObject {
    @Published var pane: SettingsPane?

    init(pane: SettingsPane) { self.pane = pane }
}

struct SettingsView: View {
    static let windowID = "settings"

    @StateObject private var navigation: SettingsNavigation

    init(pane: SettingsPane = .schedule) {
        _navigation = StateObject(wrappedValue: SettingsNavigation(pane: pane))
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $navigation.pane) { pane in
                HStack(spacing: 9) {
                    ModuleIcon(systemImage: pane.systemImage, color: pane.color, size: 22)
                    Text(pane.title)
                }
                .padding(.vertical, 2)
                .tag(pane)
            }
            .navigationSplitViewColumnWidth(200)
        } detail: {
            let pane = navigation.pane ?? .schedule
            detail(for: pane)
                .navigationTitle(pane.title)
        }
        .frame(width: 740, height: 560)
    }

    @ViewBuilder
    private func detail(for pane: SettingsPane) -> some View {
        switch pane {
        case .schedule: SchedulePane()
        case .weather: WeatherPane()
        case .homeAssistant: HomeAssistantPane()
        case .wallpaper: WallpaperPane()
        case .warmth: WarmthPane()
        case .general: GeneralPane()
        }
    }
}

// MARK: - Helpers

/// Binds a "minutes since midnight" preference to a time picker.
private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
    Binding(
        get: { Calendar.current.date(on: Date(), minutes: minutes.wrappedValue) },
        set: {
            let components = Calendar.current.dateComponents([.hour, .minute], from: $0)
            minutes.wrappedValue = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        }
    )
}

/// Explanatory text under a section, left-aligned and secondary.
private struct Footnote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Label on the left, current value and stepper on the right.
private struct StepperRow: View {
    let title: String
    let value: String
    @Binding var number: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Text(value).monospacedDigit()
                Stepper(title, value: $number, in: range, step: step).labelsHidden()
            }
        }
    }
}

/// Sun-relative transition: effective time, offset, and a stepper.
private struct OffsetRow: View {
    let title: String
    let reference: Date?
    let referenceName: String
    @Binding var offset: Int

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 0) {
                    if let reference {
                        Text(reference.addingTimeInterval(Double(offset) * 60).shortTime).monospacedDigit()
                    }
                    Text(offsetDescription).font(.caption).foregroundStyle(.secondary)
                }
                Stepper(title, value: $offset, in: -120...120, step: 5).labelsHidden()
            }
        }
    }

    private var offsetDescription: String {
        guard offset != 0 else { return "au \(referenceName)" }
        let value = abs(offset)
        let amount = value >= 60 ? "\(value / 60) h \(String(format: "%02d", value % 60))" : "\(value) min"
        return "\(referenceName) \(offset > 0 ? "+" : "−") \(amount)"
    }
}

// MARK: - Panes

struct SchedulePane: View {
    @EnvironmentObject private var engine: Engine
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var location: LocationProvider

    var body: some View {
        Form {
            Section {
                Picker("Déclenchement", selection: $prefs.scheduleMode) {
                    ForEach(ScheduleMode.allCases) { Text($0.label).tag($0) }
                }
                switch prefs.scheduleMode {
                case .solar:
                    OffsetRow(title: "Passage en clair", reference: engine.sunTimes?.sunrise, referenceName: "lever", offset: $prefs.sunriseOffset)
                    OffsetRow(title: "Passage en sombre", reference: engine.sunTimes?.sunset, referenceName: "coucher", offset: $prefs.sunsetOffset)
                case .custom:
                    DatePicker("Passage en clair", selection: timeBinding($prefs.lightTime), displayedComponents: .hourAndMinute)
                    DatePicker("Passage en sombre", selection: timeBinding($prefs.darkTime), displayedComponents: .hourAndMinute)
                case .ambient:
                    LabeledContent("Luminosité actuelle", value: engine.ambientLux.map { "\(Int($0.rounded())) lx" } ?? "—")
                case .manual:
                    EmptyView()
                }
            } header: {
                Text("Mode clair / sombre")
            } footer: {
                Footnote(modeFootnote)
            }

            Section {
                Toggle("Saisir la position manuellement", isOn: $prefs.useManualLocation)
                if prefs.useManualLocation {
                    TextField("Latitude", value: $prefs.manualLatitude, format: .number.precision(.fractionLength(4)))
                    TextField("Longitude", value: $prefs.manualLongitude, format: .number.precision(.fractionLength(4)))
                } else {
                    LabeledContent("Position") {
                        HStack(spacing: 8) {
                            Text(locationDescription).foregroundStyle(location.isDenied ? .red : .secondary)
                            Button("Actualiser") { location.refresh() }.controlSize(.small)
                        }
                    }
                }
            } header: {
                Text("Position")
            } footer: {
                Footnote("Les horaires solaires sont calculés sur ce Mac. Sans position, les horaires fixes servent de repli.")
            }
        }
        .formStyle(.grouped)
    }

    private var modeFootnote: String {
        switch prefs.scheduleMode {
        case .solar: return "Recalculé chaque jour. Décalage possible de deux heures avant ou après."
        case .custom: return "Les mêmes horaires tous les jours."
        case .ambient: return "Piloté par le capteur configuré dans Home Assistant. Retour au soleil si le capteur ne répond plus."
        case .manual: return "Bascule uniquement depuis le menu ou avec ⌃⌥⌘D."
        }
    }

    private var locationDescription: String {
        if location.isDenied { return "Accès refusé" }
        guard let coordinate = location.coordinate else { return "En attente…" }
        return location.placeName ?? String(format: "%.2f, %.2f", coordinate.latitude, coordinate.longitude)
    }
}

struct WeatherPane: View {
    @EnvironmentObject private var engine: Engine
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        Form {
            Section {
                Toggle("Passer en sombre par temps couvert", isOn: $prefs.weatherEnabled)
                LabeledContent("Seuil de nébulosité") {
                    HStack {
                        Slider(value: Binding(get: { prefs.cloudThreshold }, set: { prefs.cloudThreshold = ($0 / 5).rounded() * 5 }), in: 30...100)
                            .frame(width: 200)
                        Text("\(Int(prefs.cloudThreshold)) %").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                .disabled(!prefs.weatherEnabled)
                LabeledContent("Unité") {
                    Picker("Unité", selection: $prefs.useFahrenheit) {
                        Text("°C").tag(false)
                        Text("°F").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 110)
                }
            } footer: {
                Footnote("La prévision du matin décide de la journée entière : moyenne de la couverture nuageuse entre lever et coucher, ou orage annoncé. Données Open-Meteo, position arrondie à 1 km environ.")
            }

            if prefs.weatherEnabled, let weather = engine.weather {
                Section("Aujourd'hui") {
                    HStack(spacing: 12) {
                        Image(systemName: WeatherCode.systemImage(weather.weatherCode))
                            .symbolRenderingMode(.multicolor)
                            .font(.largeTitle)
                        VStack(alignment: .leading) {
                            Text(WeatherCode.label(weather.weatherCode)).font(.headline)
                            Text("Nuages \(Int(weather.cloudCover)) % · Indice UV \(Int(weather.uvIndex.rounded()))")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(temperature(weather.temperature)).font(.title.weight(.semibold)).monospacedDigit()
                    }
                    .padding(.vertical, 4)
                    LabeledContent("Décision du jour", value: engine.weatherForcesDark ? "Journée sombre" : "Suivre le soleil")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func temperature(_ celsius: Double) -> String {
        prefs.useFahrenheit ? "\(Int((celsius * 9 / 5 + 32).rounded())) °F" : "\(Int(celsius.rounded())) °C"
    }
}

struct HomeAssistantPane: View {
    @EnvironmentObject private var engine: Engine
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        Form {
            Section {
                TextField("URL", text: $prefs.haURL, prompt: Text("https://homeassistant.local:8123"))
                SecureField("Jeton d'accès", text: $prefs.haToken, prompt: Text("Jeton longue durée"))
                LabeledContent {
                    HStack(spacing: 8) {
                        if engine.haConnection == .checking { ProgressView().controlSize(.small) }
                        Button("Tester la connexion") { Task { await engine.testHomeAssistant() } }
                            .disabled(engine.haConnection == .checking)
                    }
                } label: {
                    connectionStatus
                }
            } header: {
                Text("Connexion")
            } footer: {
                Footnote("Jeton à créer dans Home Assistant : profil › Sécurité › Jetons d'accès longue durée. Il est stocké dans le trousseau macOS.")
            }

            Section {
                if engine.ambientSensors.isEmpty {
                    TextField("Entité", text: $prefs.haEntityID, prompt: Text("sensor.salon_illuminance"))
                } else {
                    Picker("Capteur", selection: $prefs.haEntityID) {
                        Text("Aucun").tag("")
                        ForEach(engine.ambientSensors) { sensor in
                            Text("\(sensor.name) · \(sensor.lux.map { "\(Int($0.rounded())) lx" } ?? "indisponible")").tag(sensor.id)
                        }
                        if !prefs.haEntityID.isEmpty, !engine.ambientSensors.contains(where: { $0.id == prefs.haEntityID }) {
                            Text(prefs.haEntityID).tag(prefs.haEntityID)
                        }
                    }
                }
                if let error = engine.sensorListError {
                    Notice(text: error, systemImage: "exclamationmark.triangle.fill", color: .orange)
                }
                LabeledContent("Mesure actuelle") {
                    HStack(spacing: 8) {
                        Text(engine.ambientLux.map { "\(Int($0.rounded())) lx" } ?? "—").monospacedDigit()
                        Button("Lire") { Task { await engine.refreshAmbient() } }
                            .controlSize(.small)
                            .disabled(prefs.haEntityID.isEmpty)
                    }
                }
                if let error = engine.ambientError, !prefs.haEntityID.isEmpty {
                    Notice(text: error, systemImage: "exclamationmark.triangle.fill", color: .red)
                }
            } header: {
                Text("Capteur de luminosité")
            } footer: {
                Footnote(engine.ambientSensors.isEmpty
                         ? "Testez la connexion pour choisir le capteur dans une liste, ou saisissez l'identifiant de l'entité."
                         : "Seules les entités de classe « illuminance » ou mesurées en lux sont proposées.")
            }

            Section {
                LabeledContent("Sombre en dessous de") { luxField($prefs.luxDarkBelow) }
                LabeledContent("Clair au-dessus de") { luxField($prefs.luxLightAbove) }
                StepperRow(title: "Confirmation", value: "\(prefs.luxHoldMinutes) min", number: $prefs.luxHoldMinutes, range: 0...30, step: 1)
            } header: {
                Text("Seuils")
            } footer: {
                Footnote("Entre les deux seuils, rien ne change. Une mesure doit franchir un seuil pendant toute la durée de confirmation pour déclencher la bascule : un nuage qui passe ou une lampe allumée ne fait pas clignoter l'écran. Le mode s'active dans Planning.")
            }
        }
        .formStyle(.grouped)
        .onChange(of: prefs.haURL) { _ in engine.resetHomeAssistantStatus() }
        .onChange(of: prefs.haToken) { _ in engine.resetHomeAssistantStatus() }
        .task {
            if engine.haConnection == .unknown, !prefs.haToken.isEmpty { await engine.testHomeAssistant() }
        }
    }

    private func luxField(_ value: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            TextField("", value: value, format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Text("lx").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var connectionStatus: some View {
        switch engine.haConnection {
        case .unknown:
            Notice(text: "Connexion non testée", systemImage: "circle.dashed", color: .secondary)
        case .checking:
            Notice(text: "Connexion en cours…", systemImage: "arrow.triangle.2.circlepath", color: .secondary)
        case .connected(let description):
            Notice(text: "Connecté à \(description)", systemImage: "checkmark.circle.fill", color: .green)
        case .failed(let message):
            Notice(text: message, systemImage: "xmark.octagon.fill", color: .red)
        }
    }
}

struct WallpaperPane: View {
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    WallpaperCard(title: "Mode clair", isDark: false, path: $prefs.lightWallpaper)
                    WallpaperCard(title: "Mode sombre", isDark: true, path: $prefs.darkWallpaper)
                }
                .padding(.vertical, 6)
            } footer: {
                Footnote("Appliqué sur tous les écrans à chaque changement de mode. macOS ne permet de modifier que le bureau affiché sur chaque écran, pas les autres Spaces.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct WallpaperCard: View {
    let title: String
    let isDark: Bool
    @Binding var path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            preview
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(path.isEmpty ? "Aucun fond choisi" : URL(fileURLWithPath: path).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 6) {
                Button("Choisir…", action: choose)
                Button("Fond actuel") { path = Wallpaper.current ?? path }
                if !path.isEmpty {
                    Button { path = "" } label: { Image(systemName: "xmark") }
                        .help("Retirer")
                }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var preview: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Color.clear
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay {
                if let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        shape.fill(.quaternary)
                        Image(systemName: "photo").font(.title2).foregroundStyle(.tertiary)
                    }
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.separator))
            .overlay(alignment: .topLeading) {
                ModeBadge(isDark: isDark, size: 22).padding(6)
            }
            .onTapGesture(perform: choose)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { path = url.path }
    }
}

struct WarmthPane: View {
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        Form {
            Section {
                Toggle("Réchauffer l'écran le soir", isOn: $prefs.warmthEnabled)
                Picker("Début", selection: $prefs.warmthStart) {
                    ForEach(WarmthStart.allCases) { Text($0.label).tag($0) }
                }
                if prefs.warmthStart == .customTime {
                    DatePicker("Heure", selection: timeBinding($prefs.warmthStartTime), displayedComponents: .hourAndMinute)
                }
                LabeledContent("Température") {
                    KelvinSlider(kelvin: $prefs.warmthKelvin).frame(width: 260)
                }
                StepperRow(title: "Transition", value: "\(prefs.warmthTransition) min", number: $prefs.warmthTransition, range: 5...120, step: 5)
            } footer: {
                Footnote("Passe progressivement de 6500 K (lumière du jour) à la température choisie, puis revient au neutre après le lever du soleil.")
            }

            Section {
                Picker("Rendu", selection: $prefs.warmthRenderer) {
                    ForEach(WarmthRenderer.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Suspendre Night Shift pendant la chaleur", isOn: $prefs.suspendNightShift)
            } header: {
                Text("Compatibilité")
            } footer: {
                Footnote("Si l'écran ne change pas de teinte (certains écrans récents ou HDR ignorent la table gamma), choisissez le rendu Compatibilité.")
            }
        }
        .formStyle(.grouped)
    }
}

struct GeneralPane: View {
    @EnvironmentObject private var prefs: Preferences
    @StateObject private var loginItem = LoginItem()

    var body: some View {
        Form {
            Section("Démarrage") {
                Toggle("Lancer à l'ouverture de session", isOn: $loginItem.isEnabled)
            }
            Section("Raccourcis clavier") {
                Toggle("Activer les raccourcis globaux", isOn: $prefs.hotkeysEnabled)
                LabeledContent("Basculer clair / sombre") { KeyCaps("⌃⌥⌘D") }
                LabeledContent("Basculer la chaleur") { KeyCaps("⌃⌥⌘W") }
            }
            Section("Confidentialité") {
                Group {
                    Label("Aucun compte, aucune télémétrie", systemImage: "hand.raised.fill")
                    Label("La position ne quitte pas ce Mac", systemImage: "location.fill")
                    Label("Seule la météo, si elle est activée, envoie une position arrondie à Open-Meteo", systemImage: "cloud.fill")
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct KeyCaps: View {
    let keys: String

    init(_ keys: String) { self.keys = keys }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys).map(String.init), id: \.self) { key in
                Text(key)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .frame(minWidth: 20, minHeight: 20)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
    }
}

@MainActor
private final class LoginItem: ObservableObject {
    var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            if newValue { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
        }
    }
}
