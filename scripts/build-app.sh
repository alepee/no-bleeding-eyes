#!/usr/bin/env bash
# Builds NoBleedingEyes.app into ./build. Usage: scripts/build-app.sh [debug|release]
#
# Optional environment:
#   VERSION          marketing version written to Info.plist (default: value in Resources/Info.plist)
#   BUILD_NUMBER     CFBundleVersion (default: value in Resources/Info.plist)
#   UNIVERSAL=1      build for arm64 and x86_64
#   SIGN_IDENTITY    codesign identity, name or SHA-1 (default: ad-hoc). A stable identity, even
#                    self-signed, keeps macOS permissions across updates.
#   SIGN_TIMESTAMP=1 request a secure timestamp (required for notarization, Developer ID only)
set -euo pipefail
cd "$(dirname "$0")/.."

config="${1:-release}"
build_args=(-c "$config")
if [[ "${UNIVERSAL:-0}" == 1 ]]; then
  build_args+=(--arch arm64 --arch x86_64)
fi
swift build "${build_args[@]}"
bin_path="$(swift build "${build_args[@]}" --show-bin-path)"

app="build/NoBleedingEyes.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_path/NoBleedingEyes" "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/"

plist="$app/Contents/Info.plist"
[[ -n "${VERSION:-}" ]] && /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION#v}" "$plist"
[[ -n "${BUILD_NUMBER:-}" ]] && /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$plist"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  timestamp=()
  [[ "${SIGN_TIMESTAMP:-0}" == 1 ]] && timestamp=(--timestamp)
  codesign --force ${timestamp[@]+"${timestamp[@]}"} --options runtime \
    --entitlements Resources/NoBleedingEyes.entitlements \
    --sign "$SIGN_IDENTITY" "$app"
else
  codesign --force --sign - "$app"
fi

echo "Built $app"
