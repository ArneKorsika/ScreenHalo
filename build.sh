#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
app="build/ScreenHalo.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -O -parse-as-library -target "$(uname -m)-apple-macosx14.0" Sources/ScreenHalo/Branding.swift Tools/MakeIcon.swift -o build/MakeIcon
build/MakeIcon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$app/Contents/Resources/ScreenHalo.icns"
cp .build/release/ScreenHalo "$app/Contents/MacOS/ScreenHalo.new"
mv -f "$app/Contents/MacOS/ScreenHalo.new" "$app/Contents/MacOS/ScreenHalo"
cp Info.plist "$app/Contents/Info.plist"
cp LICENSE "$app/Contents/Resources/LICENSE"
touch "$app"
signing_identity="${SCREENHALO_SIGN_IDENTITY:--}"
if [[ "$signing_identity" == "-" ]]; then
    codesign --force --sign - --entitlements ScreenHalo.entitlements "$app"
else
    codesign --force --sign "$signing_identity" --options runtime --timestamp --entitlements ScreenHalo.entitlements "$app"
fi
codesign --verify --strict "$app"
echo "Built $app"
