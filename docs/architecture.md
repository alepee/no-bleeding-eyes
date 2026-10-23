# Architecture

## Overview

```
App.swift                  MenuBarExtra + settings window, AppDelegate (launch, shutdown, --snapshot)
Core/
  Engine.swift             decision engine, the only part that acts on the system
  Preferences.swift        persisted settings (UserDefaults, Home Assistant token in the Keychain)
  SolarCalculator.swift    sunrise / sunset (NOAA equation)
  LocationProvider.swift   cached CoreLocation position
  WeatherService.swift     Open-Meteo forecast, WMO codes
  HomeAssistantClient.swift  Home Assistant REST API, Keychain
System/
  SystemAppearance.swift   read and switch light / dark
  Wallpaper.swift          per-display wallpapers
  Warmth.swift             colour temperature: gamma, overlay, Night Shift
  HotKeyCenter.swift       global shortcuts (Carbon)
Views/
  MenuContentView.swift    menu and shared components (Module, ModuleIcon, KelvinSlider…)
  SettingsView.swift       sidebar settings, one pane per feature
  Snapshotter.swift        PNG rendering of the views (debug only)
```

## Decision engine

`Engine` runs a **tick** every 15 seconds, on every settings or location change, on wake and on every display reconfiguration. A tick is idempotent: it recomputes the desired state from the time, the settings and the latest readings, then only acts on what differs.

Tick order:

1. Today's solar times; location refresh if older than 6 h.
2. Weather: new request every 30 minutes. The **first forecast of the day** sets the "dark day" decision, so the screen does not flip with every update.
3. Ambient light: sensor read every 30 seconds, then hysteresis (dark threshold, light threshold) and confirmation delay.
4. Appearance: state planned by the schedule, then any manual override.
5. Wallpaper matching the mode, applied only when it changed.
6. Warmth: factor 0 → 1 fading in from the start time, then 1 → 0 after sunrise.
7. Keyboard shortcuts, registered or removed according to the setting.

### Manual override

A toggle from the menu, the shortcut or System Settings creates an **override**. The schedule state at the time of the toggle is remembered; the override drops as soon as the schedule changes state (sunrise, sunset, dark day, lux threshold crossed). Warmth works the same way.

### Fallbacks

- No location: fixed times.
- No sun (polar night or day): fixed times.
- Home Assistant sensor silent for 10 minutes: solar schedule.

## System integrations

| Feature | Mechanism | Permission |
| --- | --- | --- |
| Light / dark | `SLSSetAppearanceThemeLegacy` (SkyLight, private), AppleScript fallback through System Events | none, or Automation for the fallback |
| Wallpapers | `NSWorkspace.setDesktopImageURL`, active desktop of each display only | none |
| Warmth, standard rendering | gamma tables (`CGSetDisplayTransferByTable`), ColorSync calibration restored on quit and launch | none |
| Warmth, compatibility rendering | transparent amber window above everything, click-through | none |
| Night Shift | `CBBlueLightClient` (CoreBrightness, private) | none |
| Shortcuts | `RegisterEventHotKey` (Carbon) | none |
| Location | CoreLocation, kilometre accuracy | Location Services |
| Home Assistant | `GET /api/config`, `/api/states`, `/api/states/<entity>` with a Bearer token | Local Network if the URL is local |

Private APIs are loaded dynamically (`dlopen`, `NSClassFromString`): if a macOS update removes them, the feature turns off without crashing.

## Distribution

`scripts/build-app.sh` assembles the bundle. `UNIVERSAL=1` builds for arm64 and x86_64, `VERSION` and `BUILD_NUMBER` stamp `Info.plist`, and `SIGN_IDENTITY` signs with the hardened runtime and `Resources/NoBleedingEyes.entitlements` (Apple Events, location). `scripts/package.sh` produces the DMG and the zip, and notarizes them when an App Store Connect API key is provided.

## Privacy

No account, no telemetry. The location feeds the solar computation on the Mac and the city name (Apple geocoding). Only the weather, when enabled, sends a location rounded to 0.01° to Open-Meteo.
