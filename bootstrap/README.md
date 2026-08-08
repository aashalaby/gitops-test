# Bootstrap

The chicken-and-egg problem: Argo CD has to exist before it can manage
anything, including itself. This directory resolves it in three steps.

1. `install.sh` renders the argo-cd chart and applies it directly. This is
   the only time anything is applied outside of Git.
2. `root-app.yaml` is applied, pointing at `clusters/prod`.
3. `clusters/prod/argocd.yaml` re-declares Argo CD using the *same chart
   version and the same values file*. Argo CD's first reconciliation of
   itself is therefore a no-op, and it takes over management cleanly.

## The version pin invariant

`CHART_VERSION` in `install.sh` and `targetRevision` in
`clusters/prod/argocd.yaml` must match. If they don't, Argo CD's first
self-sync will change its own version out from under you mid-bootstrap.
Renovate is configured to bump both together.

## Disaster recovery

Rebuilding a cluster from scratch is: create cluster, run `install.sh`,
wait. Anything not reproducible by that path is a gap — most commonly
secrets and PersistentVolume data, which is why the secrets backend lives
outside the cluster.
