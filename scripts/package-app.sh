#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app=build/Orator.app
archive=build/Orator-macOS-arm64.zip
image=build/Orator-macOS-arm64.dmg
staging=$(mktemp -d "${TMPDIR:-/tmp}/orator-package.XXXXXX")
mountpoint=$(mktemp -d "${TMPDIR:-/tmp}/orator-mount.XXXXXX")
mounted=false
cleanup() {
    if [[ "$mounted" == true ]]; then hdiutil detach "$mountpoint" -quiet || true; fi
    rm -rf "$staging" "$mountpoint"
}
trap cleanup EXIT
codesign --verify --deep --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
ditto "$app" "$staging/Orator.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname Orator -srcfolder "$staging" -format UDZO -ov "$image"
hdiutil verify "$image"
hdiutil attach "$image" -nobrowse -readonly -mountpoint "$mountpoint" -quiet
mounted=true
codesign --verify --deep --strict "$mountpoint/Orator.app"
[[ "$(readlink "$mountpoint/Applications")" == /Applications ]]
cmp "$app/Contents/Info.plist" "$mountpoint/Orator.app/Contents/Info.plist"
hdiutil detach "$mountpoint" -quiet
mounted=false
shasum -a 256 "$archive" "$image" > build/SHA256SUMS
