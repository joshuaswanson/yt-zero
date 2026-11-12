#!/bin/bash
# Builds the app, signs the DMG for Sparkle, and publishes it with its appcast
# as the GitHub release for the version in Info.plist.
# The Sparkle signing key lives in the login Keychain (generate_keys).
set -euo pipefail
cd "$(dirname "$0")"

if [ -n "$(git status --porcelain)" ]; then
  echo "Commit or stash your changes first" >&2
  exit 1
fi

./build.sh

version="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)"
build="$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Info.plist)"
tag="v$version"
repo="joshuaswanson/yt-zero"
dmg="../build/YT-Zero.dmg"
appcast="../build/appcast.xml"
sparkle_bin="$(ls -d .cache/Sparkle-*/bin | tail -1)"

signature="$("$sparkle_bin/sign_update" "$dmg")"
cat > "$appcast" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>YT Zero</title>
    <item>
      <title>$version</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/$repo/releases/tag/$tag</sparkle:releaseNotesLink>
      <enclosure url="https://github.com/$repo/releases/download/$tag/YT-Zero.dmg" type="application/octet-stream" $signature />
    </item>
  </channel>
</rss>
XML

notes="Open YT-Zero.dmg and drag YT Zero onto the Applications folder. Needs a Mac with Apple silicon and macOS 15 or later. The app is not notarized, so on first launch open System Settings, go to Privacy & Security, and click Open Anyway. Installed copies update themselves."
if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
  gh release upload "$tag" "$dmg" "$appcast" --repo "$repo" --clobber
else
  git push origin HEAD
  gh release create "$tag" "$dmg" "$appcast" --repo "$repo" --title "YT Zero $version" --notes "$notes" --target "$(git rev-parse HEAD)"
fi
echo "Released $tag"
