#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
output_root="${1:-$project_root/dist}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_root/Resources/Info.plist")"
architecture="arm64"
app="$output_root/FootageFlow.app"
dmg_name="FootageFlow-${version}-macOS-${architecture}.dmg"
dmg="$output_root/$dmg_name"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

mkdir -p "$output_root"
"$project_root/scripts/build_app.sh" "$output_root"

if [[ "$(lipo -archs "$app/Contents/MacOS/FootageFlow")" != *arm64* ]]; then
  printf 'Release executable is not arm64.\n' >&2
  exit 1
fi

cp -R "$app" "$staging/FootageFlow.app"
ln -s /Applications "$staging/Applications"

hdiutil create \
  -volname "FootageFlow $version" \
  -srcfolder "$staging" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$dmg" >/dev/null

(
  cd "$output_root"
  shasum -a 256 "$dmg_name" > "$dmg_name.sha256"
)

printf '%s\n%s\n' "$dmg" "$dmg.sha256"
