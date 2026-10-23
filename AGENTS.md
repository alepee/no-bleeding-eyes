# AGENTS.md

App de barre de menus macOS (SwiftUI, package Swift sans projet Xcode). Architecture et intégrations système : [`docs/architecture.md`](docs/architecture.md), à lire avant de toucher à `Engine` ou à `System/`.

## Langue

Interface et documentation en français ; code, identifiants et commits en anglais. Commits au format Karma : `type(scope): subject`.

## Compiler et vérifier

- Compiler avec `scripts/build-app.sh debug`. Les Command Line Tools suffisent, mais leurs SDK récents n'embarquent pas les plugins de macros SwiftUI : utiliser `@StateObject` et un `ObservableObject` à la place de `@State`, et éviter toute autre macro (`@Observable`, `#Preview`).
- Les tests (`swift test`, XCTest) demandent Xcode ; sans Xcode, la CI GitHub les exécute.
- Vérifier chaque changement d'interface sur des captures : `build/NoBleedingEyes.app/Contents/MacOS/NoBleedingEyes --snapshot <dossier>`, puis regarder les PNG clair et sombre. Une vue ou un panneau ajouté s'inscrit dans `Snapshotter`, et ses données d'exemple dans `Engine.preview()`.
- Lancer l'app (`open build/NoBleedingEyes.app`) agit sur le vrai système : apparence, gamma, fond d'écran, Night Shift. Le mode `--snapshot` n'y touche pas.

## Conventions du code

- `Engine` est le seul à appeler `System/`. Les vues lisent l'état publié et passent par les méthodes de `Engine` ou les réglages de `Preferences`.
- Chaque réglage est une propriété `@Published` de `Preferences`, persistée dans son `didSet` ; un secret va dans le trousseau (`Keychain`).
- Messages d'erreur destinés à l'utilisateur : une phrase complète qui nomme la cause et, si possible, l'action à faire.
- Composants d'interface partagés dans `MenuContentView.swift` (`Module`, `ModuleIcon`, `ModeBadge`, `KelvinSlider`, `Notice`) : les réutiliser pour garder le menu et les réglages cohérents.
