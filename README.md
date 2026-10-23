# No Bleeding Eyes

[![CI](https://github.com/alepee/no-bleeding-eyes/actions/workflows/ci.yml/badge.svg)](https://github.com/alepee/no-bleeding-eyes/actions/workflows/ci.yml)

App de barre de menus macOS qui accorde l'écran au moment de la journée : mode clair ou sombre, fond d'écran, température de couleur. Inspirée de [Solace](https://www.theodorehq.com/solace/).

<p>
  <img src="docs/screenshots/menu-light.png" width="300" alt="Menu, mode clair">
  <img src="docs/screenshots/menu-dark.png" width="300" alt="Menu, mode sombre">
</p>

## Fonctionnalités

- **Planning clair / sombre** : lever et coucher du soleil calculés sur le Mac, avec un décalage de ±2 h pour chacun ; ou horaires fixes ; ou manuel.
- **Météo** : la première prévision du jour décide si toute la journée passe en sombre (couverture nuageuse moyenne au-dessus d'un seuil, ou orage). Affiche ciel, température (°C/°F), nuages, pluie et UV. Données [Open-Meteo](https://open-meteo.com), position arrondie à 1 km environ.
- **Luminosité ambiante (Home Assistant)** : un capteur de lux pilote le mode. Deux seuils (hystérésis) et un délai de confirmation évitent le clignotement. Retour au soleil si le capteur ne répond plus pendant 10 minutes. Jeton stocké dans le trousseau.
- **Fonds d'écran** : un pour le mode clair, un pour le mode sombre, appliqués sur tous les écrans.
- **Chaleur du soir** : transition progressive de 6500 K vers la température choisie (jusqu'à 1900 K), au coucher du soleil, à heure fixe ou en continu ; retour au neutre après le lever. Rendu par table gamma, ou par filtre superposé pour les écrans qui ignorent le gamma. Night Shift est suspendu pendant ce temps pour ne pas cumuler les filtres.
- **Raccourcis globaux** : `⌃⌥⌘D` bascule clair / sombre, `⌃⌥⌘W` bascule la chaleur. Une bascule manuelle (ou un changement fait dans les Réglages Système) tient jusqu'au prochain changement prévu.
- Lancement à l'ouverture de session, multi-écrans, aucun compte, aucune télémétrie.

## Installation

Télécharger le zip d'une [release](https://github.com/alepee/no-bleeding-eyes/releases) ou l'artefact du dernier passage de la CI, puis glisser l'app dans `/Applications`. L'app n'est pas notariée : au premier lancement, clic droit › Ouvrir.

## Développement

macOS 13 minimum. Les Command Line Tools suffisent pour compiler ; les tests demandent Xcode (XCTest n'est pas fourni avec les Command Line Tools).

```sh
scripts/build-app.sh            # build release → build/NoBleedingEyes.app (signature ad hoc)
scripts/build-app.sh debug
open build/NoBleedingEyes.app
swift test                      # avec Xcode
```

Publier une version : pousser un tag `vX.Y.Z`, le workflow `Release` crée la release GitHub avec le zip.

### Captures d'écran

Les builds debug rendent chaque vue en PNG, en clair et en sombre, avec des données d'exemple et sans toucher au système :

```sh
scripts/build-app.sh debug
build/NoBleedingEyes.app/Contents/MacOS/NoBleedingEyes --snapshot docs/screenshots
```

| Planning | Home Assistant | Chaleur du soir |
| --- | --- | --- |
| ![](docs/screenshots/settings-schedule-light.png) | ![](docs/screenshots/settings-homeAssistant-light.png) | ![](docs/screenshots/settings-warmth-light.png) |
| **Météo** | **Fonds d'écran** | **Général** |
| ![](docs/screenshots/settings-weather-dark.png) | ![](docs/screenshots/settings-wallpaper-dark.png) | ![](docs/screenshots/settings-general-dark.png) |

## Documentation

- [Architecture](docs/architecture.md) : moteur de décision, intégrations système, API privées.
