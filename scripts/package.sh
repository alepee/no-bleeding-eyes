#!/usr/bin/env bash
# Packages build/NoBleedingEyes.app into build/NoBleedingEyes.dmg and build/NoBleedingEyes.zip.
# Usage: scripts/package.sh
#
# When NOTARY_KEY_PATH, NOTARY_KEY_ID and NOTARY_ISSUER are set, the DMG is notarized
# with an App Store Connect API key and the ticket is stapled to the app and the DMG.
set -euo pipefail
cd "$(dirname "$0")/.."

app="build/NoBleedingEyes.app"
dmg="build/NoBleedingEyes.dmg"
zip="build/NoBleedingEyes.zip"
[[ -d "$app" ]] || { echo "Missing $app, run scripts/build-app.sh first" >&2; exit 1; }

notarize() {
  xcrun notarytool submit "$1" --wait \
    --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER"
  xcrun stapler staple "$1"
}

if [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
  # The app is notarized first so the zip carries a stapled ticket too.
  ditto -c -k --keepParent "$app" "$zip"
  notarize "$zip"
  xcrun stapler staple "$app"
fi

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
hdiutil create -volname "No Bleeding Eyes" -srcfolder "$staging" -fs HFS+ -format UDZO "$dmg"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  timestamp=()
  [[ "${SIGN_TIMESTAMP:-0}" == 1 ]] && timestamp=(--timestamp)
  codesign --force ${timestamp[@]+"${timestamp[@]}"} --sign "$SIGN_IDENTITY" "$dmg"
fi
[[ -n "${NOTARY_KEY_PATH:-}" ]] && notarize "$dmg"

rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

echo "Packaged $dmg and $zip"
