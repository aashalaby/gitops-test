#!/usr/bin/env bash
# Preview what Argo CD would change for a given Application, without syncing.
# Requires `argocd login` first.
set -euo pipefail

APP="${1:-}"
if [[ -z "$APP" ]]; then
  echo "usage: $0 <application-name> [--revision <git-sha-or-branch>]" >&2
  echo "example: $0 demo-app-prod --revision \$(git rev-parse HEAD)" >&2
  exit 1
fi
shift

argocd app diff "$APP" "$@"
