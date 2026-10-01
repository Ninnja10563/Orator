#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
arch="${ORATOR_ARCH:-arm64}"
swift build -c release --arch "$arch"
bin_dir="$(swift build -c release --arch "$arch" --show-bin-path)"
app="build/Orator.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Orator" "$app/Contents/MacOS/Orator"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift build/Orator.iconset
iconutil --convert icns build/Orator.iconset --output "$app/Contents/Resources/Orator.icns"
identity="${ORATOR_SIGN_IDENTITY:--}"
if [[ "$identity" == '-' ]]; then
  codesign --force --sign - "$app"
else
  codesign --force --sign "$identity" --options runtime --timestamp "$app"
fi
codesign --verify --deep --strict "$app"
printf 'Built %s\n' "$app"
