#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

temp_file="$(mktemp)"
trap 'rm -f "$temp_file"' EXIT

markdown_files=("${(@f)$(rg --files -g '*.md' | LC_ALL=C sort)}")
(( ${#markdown_files[@]} > 0 )) || { printf 'No Markdown files found.\n'; exit 1; }

/usr/bin/perl -ne '
  while (/!?\[[^]]*\]\(([^)]+)\)/g) {
    print "$ARGV\t$.\t$1\n";
  }
  close ARGV if eof;
' "${markdown_files[@]}" > "$temp_file"

failures=0
while IFS=$'\t' read -r source line target; do
  target="${target#<}"
  target="${target%>}"
  case "$target" in
    http://*|https://*|mailto:*|'#'*) continue ;;
  esac

  clean_target="${target%%#*}"
  clean_target="${clean_target%%\?*}"
  [[ -z "$clean_target" ]] && continue

  resolved="$(dirname "$source")/$clean_target"
  if [[ ! -e "$resolved" ]]; then
    printf 'Broken Markdown link: %s:%s -> %s\n' "$source" "$line" "$target"
    failures=$((failures + 1))
  fi
done < "$temp_file"

(( failures == 0 )) || exit 1
printf 'MARKDOWN_LINK_CHECK passed (%s files)\n' "${#markdown_files[@]}"
