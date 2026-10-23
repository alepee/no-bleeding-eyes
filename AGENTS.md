# AGENTS.md

macOS menu bar app (SwiftUI, Swift package without an Xcode project). Architecture and system integrations: [`docs/architecture.md`](docs/architecture.md), read it before touching `Engine` or `System/`.

## Language

The repository is public: documentation, code, identifiers and commits in English. The user interface is in French. Commits follow the Karma format: `type(scope): subject`.

## Build and verify

- Build with `scripts/build-app.sh debug`. The Command Line Tools are enough, but their recent SDKs lack the SwiftUI macro plugins: use `@StateObject` and an `ObservableObject` instead of `@State`, and avoid any other macro (`@Observable`, `#Preview`).
- Tests (`swift test`, XCTest) need Xcode; without Xcode, GitHub CI runs them.
- Check every interface change on snapshots: `build/NoBleedingEyes.app/Contents/MacOS/NoBleedingEyes --snapshot <dir>`, then look at the light and dark PNGs. A new view or pane registers in `Snapshotter`, and its sample data in `Engine.preview()`.
- Launching the app (`open build/NoBleedingEyes.app`) acts on the real system: appearance, gamma, wallpaper, Night Shift. `--snapshot` mode does not.
- Releases come from `v*` tags (`.github/workflows/release.yml`); the website lives in `site/` and deploys through `.github/workflows/pages.yml`.

## Code conventions

- `Engine` is the only caller of `System/`. Views read published state and go through `Engine` methods or `Preferences` settings.
- Each setting is a `@Published` property of `Preferences`, persisted in its `didSet`; a secret goes in the Keychain (`Keychain`).
- User-facing error messages: one complete sentence naming the cause and, when possible, the action to take.
- Shared interface components live in `MenuContentView.swift` (`Module`, `ModuleIcon`, `ModeBadge`, `KelvinSlider`, `Notice`): reuse them to keep the menu and settings consistent.
