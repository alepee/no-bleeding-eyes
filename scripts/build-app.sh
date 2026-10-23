#!/usr/bin/env bash
# Builds NoBleedingEyes.app into ./build (ad-hoc signed). Usage: scripts/build-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

config="${1:-release}"
swift build -c "$config"
bin_path="$(swift build -c "$config" --show-bin-path)"

app="build/NoBleedingEyes.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_path/NoBleedingEyes" "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/"
codesign --force --sign - "$app"

echo "Built $app"
