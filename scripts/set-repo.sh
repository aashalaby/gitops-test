#!/usr/bin/env bash
# Replace the placeholder repo URL everywhere. Run this first.
#
#   ./scripts/set-repo.sh https://github.com/myorg/gitops.git
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <git-repo-url>" >&2
  exit 1
fi

NEW_URL="$1"
OLD_URL="https://github.com/ORG/gitops.git"

cd "$(dirname "$0")/.."
grep -rl "$OLD_URL" . --exclude-dir=.git | while read -r f; do
  sed -i.bak "s|$OLD_URL|$NEW_URL|g" "$f" && rm -f "$f.bak"
  echo "updated $f"
done

echo
echo "Done. Now review bootstrap/argocd-values.yaml for your domain and SSO settings."
