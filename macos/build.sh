#!/bin/bash
# Builds YT Zero.app and installs it in /Applications.
set -euo pipefail
cd "$(dirname "$0")"
app="../build/YT Zero.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macos15.0 \
  -o "$app/Contents/MacOS/YTZero" Sources/*.swift
cp Info.plist "$app/Contents/Info.plist"
cp Resources/* "$app/Contents/Resources/"

# A stable identity keeps the Full Disk Access grant valid across rebuilds.
identity=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1)
codesign --force --sign "${identity:--}" "$app"

rm -rf "/Applications/YT Zero.app"
cp -R "$app" /Applications/
echo "Installed /Applications/YT Zero.app"
