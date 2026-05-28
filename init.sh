#!/usr/bin/env bash
set -euo pipefail

OLD_DOMAIN="ggang.cloud"
NEW_DOMAIN="${1:?Usage: $0 <new-domain>}"

[[ "$OLD_DOMAIN" == "$NEW_DOMAIN" ]] && { echo "Identical, no-op."; exit 0; }

files=$(grep -rlF "$OLD_DOMAIN" \
  --include='*.yaml' --include='*.yml' --include='*.md' --include='*.sh' \
  --exclude-dir=.git --exclude-dir=docs/private \
  . 2>/dev/null || true)

if [[ -z "$files" ]]; then
  echo "No occurrences of '$OLD_DOMAIN' found."
  exit 0
fi

echo "Files to update:"
echo "$files" | sed 's/^/  /'
read -rp "Replace '$OLD_DOMAIN' -> '$NEW_DOMAIN'? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || exit 1

echo "$files" | xargs sed -i "s|${OLD_DOMAIN}|${NEW_DOMAIN}|g"

echo "Done. Review with: git diff --stat"
