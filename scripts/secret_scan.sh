#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"

if [[ ! -d .git ]]; then
    echo "Secret scan requires a local Git repository."
    exit 2
fi

patterns=(
    'sk-[A-Za-z0-9_-]{20,}'
    'AIza[0-9A-Za-z_-]{30,}'
    'gh[pousr]_[A-Za-z0-9_]{20,}'
    'BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY'
    'Bearer[[:space:]]+[A-Za-z0-9._~+/-]{20,}'
    '/Users/[^/[:space:]]+'
    '/Volumes/[^/[:space:]]+'
)

failed=0
for pattern in "${patterns[@]}"; do
    matches="$(git grep -IlE "$pattern" -- . ':(exclude)scripts/secret_scan.sh' 2>/dev/null || true)"
    if [[ -n "$matches" ]]; then
        echo "Potential sensitive pattern found in:"
        echo "$matches"
        failed=1
    fi
done

for path in ${(f)"$(git ls-files)"}; do
    lower="${path:l}"
    case "$lower" in
        *.env|*.env.*|*cookie*|*credentials*|*private_key*|*.pem|*.p12)
            echo "Potential sensitive filename: $path"
            failed=1
            ;;
    esac
done

if (( failed )); then
    echo "SECRET_SCAN failed"
    exit 1
fi

echo "SECRET_SCAN passed"
