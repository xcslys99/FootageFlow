#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
english="$repo_root/Sources/FootageFlow/Resources/en.lproj/Localizable.strings"
locales=(zh-Hans zh-Hant es pt-BR ja ko de fr ru)
temp_root="$(mktemp -d)"
trap 'rm -rf "$temp_root"' EXIT

extract_keys() {
  LC_ALL=C sed -nE 's/^"([^"]+)"[[:space:]]*=.*/\1/p' "$1" | sort -u
}

extract_placeholders() {
  /usr/bin/perl -ne 'if (/^"([^"]+)"\s*=\s*"(.*)";/) { @p = ($2 =~ /%(?:02d|d|@|%)/g); print "$1\t", join(",", @p), "\n" if @p; }' "$1" | sort
}

extract_keys "$english" > "$temp_root/en.keys"
extract_placeholders "$english" > "$temp_root/en.placeholders"
for locale in "${locales[@]}"; do
  localized="$repo_root/Sources/FootageFlow/Resources/$locale.lproj/Localizable.strings"
  [[ -f "$localized" ]] || { printf 'Missing localization file: %s\n' "$locale"; exit 1; }
  extract_keys "$localized" > "$temp_root/$locale.keys"
  comm -23 "$temp_root/en.keys" "$temp_root/$locale.keys" | grep -v '^localization\.fallbackProbe$' > "$temp_root/$locale.missing" || true
  comm -13 "$temp_root/en.keys" "$temp_root/$locale.keys" > "$temp_root/$locale.extra" || true
  if [[ -s "$temp_root/$locale.missing" || -s "$temp_root/$locale.extra" ]]; then
    [[ ! -s "$temp_root/$locale.missing" ]] || { printf 'Missing %s keys:\n' "$locale"; sed 's/^/  /' "$temp_root/$locale.missing"; }
    [[ ! -s "$temp_root/$locale.extra" ]] || { printf 'Extra %s keys:\n' "$locale"; sed 's/^/  /' "$temp_root/$locale.extra"; }
    exit 1
  fi
  extract_placeholders "$localized" > "$temp_root/$locale.placeholders"
  if ! diff -u "$temp_root/en.placeholders" "$temp_root/$locale.placeholders"; then
    printf 'Placeholder mismatch in %s localization.\n' "$locale"
    exit 1
  fi
done

plutil -lint "$english" "$repo_root"/Sources/FootageFlow/Resources/*.lproj/Localizable.strings >/dev/null
if grep -R -n -E '__FF(SEP|PH)' "$repo_root/Sources/FootageFlow/Resources"; then
  printf 'Localization generation marker remains in a resource file.\n'
  exit 1
fi
printf 'LOCALIZATION_CHECK passed\n'
