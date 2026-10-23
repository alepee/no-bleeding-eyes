# Architecture

## Vue d'ensemble

```
App.swift                  MenuBarExtra + fenêtre de réglages, AppDelegate (démarrage, arrêt, --snapshot)
Core/
  Engine.swift             moteur de décision, seul à agir sur le système
  Preferences.swift        réglages persistés (UserDefaults, jeton HA dans le trousseau)
  SolarCalculator.swift    lever / coucher du soleil (équation NOAA)
  LocationProvider.swift   position CoreLocation mise en cache
  WeatherService.swift     prévision Open-Meteo, codes WMO
  HomeAssistantClient.swift  API REST Home Assistant, trousseau
System/
  SystemAppearance.swift   lecture et bascule clair / sombre
  Wallpaper.swift          fonds d'écran par écran
  Warmth.swift             température de couleur : gamma, filtre superposé, Night Shift
  HotKeyCenter.swift       raccourcis globaux (Carbon)
Views/
  MenuContentView.swift    menu et composants partagés (Module, ModuleIcon, KelvinSlider…)
  SettingsView.swift       réglages en barre latérale, un panneau par fonction
  Snapshotter.swift        rendu PNG des vues (debug uniquement)
```

## Moteur de décision

`Engine` exécute un **tick** toutes les 15 secondes, à chaque changement de réglage ou de position, au réveil et à chaque reconfiguration des écrans. Un tick est idempotent : il recalcule l'état voulu à partir de l'heure, des réglages et des dernières mesures, puis n'agit que sur ce qui diffère.

Ordre d'un tick :

1. Horaires solaires du jour, rafraîchissement de la position si elle a plus de 6 h.
2. Météo : nouvelle requête toutes les 30 minutes. La **première prévision du jour** fixe la décision « journée sombre », pour que l'écran ne bascule pas au gré des mises à jour.
3. Luminosité ambiante : lecture du capteur toutes les 30 secondes, puis hystérésis (seuil sombre, seuil clair) et délai de confirmation.
4. Apparence : état prévu par le planning, puis forçage manuel éventuel.
5. Fond d'écran correspondant au mode, appliqué seulement s'il a changé.
6. Chaleur : facteur 0 → 1 en fondu depuis l'heure de début, puis 1 → 0 après le lever.
7. Raccourcis clavier, enregistrés ou retirés selon le réglage.

### Forçage manuel

Une bascule depuis le menu, le raccourci ou les Réglages Système crée un **forçage**. L'état du planning au moment de la bascule est mémorisé ; le forçage tombe dès que le planning change d'état (lever, coucher, journée sombre, seuil de lux franchi). Même mécanisme pour la chaleur.

### Replis

- Sans position : horaires fixes.
- Soleil absent (nuit ou jour polaire) : horaires fixes.
- Capteur Home Assistant muet depuis 10 minutes : planning solaire.

## Intégrations système

| Fonction | Mécanisme | Autorisation |
| --- | --- | --- |
| Clair / sombre | `SLSSetAppearanceThemeLegacy` (SkyLight, privée), repli AppleScript via System Events | aucune, ou Automatisation pour le repli |
| Fonds d'écran | `NSWorkspace.setDesktopImageURL`, bureau actif de chaque écran seulement | aucune |
| Chaleur, rendu standard | tables gamma (`CGSetDisplayTransferByTable`), calibrage ColorSync restauré à l'arrêt et au lancement | aucune |
| Chaleur, rendu compatibilité | fenêtre ambre transparente au-dessus de tout, qui laisse passer les clics | aucune |
| Night Shift | `CBBlueLightClient` (CoreBrightness, privée) | aucune |
| Raccourcis | `RegisterEventHotKey` (Carbon) | aucune |
| Position | CoreLocation, précision au kilomètre | Service de localisation |
| Home Assistant | `GET /api/config`, `/api/states`, `/api/states/<entité>` avec jeton Bearer | Réseau local si l'URL est locale |

Les API privées sont chargées dynamiquement (`dlopen`, `NSClassFromString`) : si une mise à jour de macOS les retire, la fonction se désactive sans planter.

## Confidentialité

Aucun compte ni télémétrie. La position sert au calcul solaire sur le Mac et au nom de ville (géocodage Apple). Seule la météo, si elle est activée, envoie une position arrondie à 0,01° à Open-Meteo.
