#!/usr/bin/env bash
# Render every kustomize directory the same way Argo CD's repo-server would.
# Used by CI; also handy locally to see what a PR actually changes.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT=/tmp/rendered
rm -rf "$OUT" && mkdir -p "$OUT"

# --enable-helm must match kustomize.buildOptions in argocd-values.yaml
KUSTOMIZE_FLAGS="--enable-helm"

find clusters platform apps -name kustomization.yaml -print0 |
  while IFS= read -r -d '' k; do
    dir="$(dirname "$k")"
    name="$(echo "$dir" | tr '/' '-')"
    echo ">> rendering $dir"
    kubectl kustomize $KUSTOMIZE_FLAGS "$dir" > "$OUT/$name.yaml"
  done

echo
echo "Rendered manifests in $OUT"
