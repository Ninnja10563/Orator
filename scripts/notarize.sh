#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ORATOR_SIGN_IDENTITY:?Set a Developer ID Application signing identity}"
: "${ORATOR_NOTARY_KEY_PATH:?Set the App Store Connect API private key path}"
: "${ORATOR_NOTARY_KEY_ID:?Set the API key ID}"
: "${ORATOR_NOTARY_ISSUER:?Set the API issuer ID}"
[[ "$ORATOR_SIGN_IDENTITY" != '-' ]] || { echo 'An ad-hoc signature cannot be notarized.' >&2; exit 1; }
app=build/Orator.app
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
archive="build/Orator-${version}-macOS-arm64.zip"
image="build/Orator-${version}-macOS-arm64.dmg"
staging=$(mktemp -d "${TMPDIR:-/tmp}/orator-dmg.XXXXXX")
trap 'rm -rf "$staging"' EXIT
codesign --verify --deep --strict "$app"
notarize() {
    local target="$1"
    local report="$2"
    xcrun notarytool submit "$target" --key "$ORATOR_NOTARY_KEY_PATH" --key-id "$ORATOR_NOTARY_KEY_ID" --issuer "$ORATOR_NOTARY_ISSUER" --wait --output-format json > "$report"
    python3 - "$report" <<'PY'
import json,sys
report=json.load(open(sys.argv[1]))
if report.get('status') != 'Accepted':
    raise SystemExit('Notarization failed. Inspect the Apple submission log for ID '+str(report.get('id')))
PY
}
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
notarize "$archive" build/notarization-app.json
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
ditto "$app" "$staging/Orator.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname Orator -srcfolder "$staging" -format UDZO -ov "$image"
codesign --force --sign "$ORATOR_SIGN_IDENTITY" --timestamp "$image"
notarize "$image" build/notarization-dmg.json
xcrun stapler staple "$image"
xcrun stapler validate "$image"
shasum -a 256 "$archive" "$image" > build/SHA256SUMS
printf 'Signed and notarized: %s\n' "$archive" "$image"
