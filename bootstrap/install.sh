#!/usr/bin/env bash
#
# The ONLY imperative step in this repo. Run once against an empty cluster.
# After this, every change — including upgrades to Argo CD itself — is a
# commit to this repository.
#
# Why `helm template | kubectl apply` instead of `helm install`:
# a Helm release leaves ownership metadata and a release Secret that Argo CD
# would later contend with. Rendering avoids the adoption conflict entirely.
set -euo pipefail

CHART_VERSION="${CHART_VERSION:-10.3.0}"
NAMESPACE="${NAMESPACE:-argocd}"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "==> Sanity check: cluster reachable?"
kubectl cluster-info >/dev/null

echo "==> Creating namespace $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Adding argo helm repo"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update argo >/dev/null

echo "==> Rendering argo-cd chart $CHART_VERSION"
helm template argocd argo/argo-cd \
  --version "$CHART_VERSION" \
  --namespace "$NAMESPACE" \
  --include-crds \
  -f "$HERE/argocd-values.yaml" \
  | kubectl apply -n "$NAMESPACE" --server-side --force-conflicts -f -

echo "==> Waiting for Argo CD to come up"
kubectl -n "$NAMESPACE" rollout status deploy/argocd-repo-server --timeout=300s
kubectl -n "$NAMESPACE" rollout status statefulset/argocd-application-controller --timeout=300s

echo "==> Applying root Application (hands control to Git)"
kubectl apply -f "$HERE/root-app.yaml"

cat <<'MSG'

Bootstrap complete.

Initial admin password:
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' | base64 -d; echo

Port-forward the UI:
  kubectl -n argocd port-forward svc/argocd-server 8080:80

IMPORTANT: the chart version pinned here must match the one in
clusters/prod/argocd.yaml. If they drift, Argo CD's first self-sync will
downgrade or upgrade itself unexpectedly.

Once SSO is configured, set `configs.cm.admin.enabled: false` in
bootstrap/argocd-values.yaml and delete argocd-initial-admin-secret.
MSG
