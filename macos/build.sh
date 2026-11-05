#!/bin/bash
# Builds YouTube Zero.app and installs it in /Applications.
set -euo pipefail
cd "$(dirname "$0")"
root=$(cd .. && pwd)
app="$root/build/YouTube Zero.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -O -swift-version 5 -o "$app/Contents/MacOS/YouTubeZero" YouTubeZero.swift
sed "s|@ROOT@|$root|" Info.plist > "$app/Contents/Info.plist"
cp AppIcon.icns "$app/Contents/Resources/"

# A stable identity keeps the Full Disk Access grant valid across rebuilds.
identity=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1)
codesign --force --sign "${identity:--}" "$app"

rm -rf "/Applications/YouTube Zero.app"
cp -R "$app" /Applications/
echo "Installed /Applications/YouTube Zero.app"
