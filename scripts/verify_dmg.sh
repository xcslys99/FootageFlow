#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_root/Resources/Info.plist")"
dmg="${1:-$project_root/dist/FootageFlow-${version}-macOS-arm64.dmg}"
checksum="$dmg.sha256"
mount_root="$(mktemp -d)"
attached=0

cleanup() {
  if (( attached )); then hdiutil detach "$mount_root" >/dev/null || true; fi
  rmdir "$mount_root" 2>/dev/null || true
}
trap cleanup EXIT

[[ -f "$dmg" && -f "$checksum" ]]
(
  cd "${dmg:h}"
  shasum -a 256 -c "${checksum:t}"
)
hdiutil verify "$dmg" >/dev/null
hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mount_root" >/dev/null
attached=1

app="$mount_root/FootageFlow.app"
[[ -d "$app" && -L "$mount_root/Applications" ]]
codesign --verify --deep --strict "$app"
plutil -lint "$app/Contents/Info.plist" >/dev/null
[[ "$(lipo -archs "$app/Contents/MacOS/FootageFlow")" == *arm64* ]]
"$app/Contents/MacOS/FootageFlow" --self-test
printf 'DMG_VERIFY passed\n'
