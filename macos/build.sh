#!/bin/bash
# Builds YT Zero.app and installs it in /Applications.
set -euo pipefail
cd "$(dirname "$0")"
app="../build/YT Zero.app"

sparkle_version=2.10.1
sparkle_sha256=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
sparkle=".cache/Sparkle-$sparkle_version"
if [ ! -d "$sparkle/Sparkle.framework" ]; then
  echo "Downloading Sparkle $sparkle_version"
  mkdir -p .cache
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$sparkle_version/Sparkle-$sparkle_version.tar.xz" -o "$sparkle.tar.xz"
  if [ "$(shasum -a 256 "$sparkle.tar.xz" | awk '{ print $1 }')" != "$sparkle_sha256" ]; then
    rm -f "$sparkle.tar.xz"
    echo "Sparkle download failed its checksum" >&2
    exit 1
  fi
  mkdir -p "$sparkle"
  tar -xJf "$sparkle.tar.xz" -C "$sparkle"
  rm -f "$sparkle.tar.xz"
fi

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp -R "$sparkle/Sparkle.framework" "$app/Contents/Frameworks/"
swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macos15.0 \
  -F "$sparkle" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$app/Contents/MacOS/YTZero" Sources/*.swift
cp Info.plist "$app/Contents/Info.plist"
cp Resources/* "$app/Contents/Resources/"

# A stable identity keeps the Full Disk Access grant valid across rebuilds.
identity=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1)
codesign --force --deep --sign "${identity:--}" "$app"

dmg="../build/YT-Zero.dmg"
staging="../build/dmg"
rm -rf "$staging" "$dmg"
mkdir -p "$staging"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname "YT Zero" -srcfolder "$staging" -fs HFS+ -format UDZO "$dmg"
rm -rf "$staging"

rm -rf "/Applications/YT Zero.app"
cp -R "$app" /Applications/
echo "Installed /Applications/YT Zero.app and built $dmg"
