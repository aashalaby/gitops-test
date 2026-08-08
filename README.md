# GitOps cluster configuration

Declarative configuration for the `prod` Kubernetes cluster, managed by
Argo CD. Argo CD manages itself from this repository.

**One imperative command exists in this whole system: `bootstrap/install.sh`.
It runs once, against an empty cluster. Everything after that is a pull
request.** If you find yourself running `kubectl apply` a second time,
something is wrong with the design, not with the tooling.

---

## Before you run anything

Three things must be done first.

### 1. Point the repo at itself

Every Application references this repo by URL, so it has to know its own
address:

```bash
./scripts/set-repo.sh https://github.com/myorg/gitops.git
```

### 2. Verify the pinned chart versions

Third-party chart versions are pinned deliberately — `targetRevision: HEAD`
on an upstream chart means a random Tuesday upgrade of your ingress
controller. But pins go stale. Check each one before the first apply:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add jetstack https://charts.jetstack.io
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add external-secrets https://charts.external-secrets.io
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm search repo argo/argo-cd --versions | head -3
helm search repo jetstack/cert-manager --versions | head -3
helm search repo ingress-nginx/ingress-nginx --versions | head -3
helm search repo external-secrets/external-secrets --versions | head -3
helm search repo prometheus-community/kube-prometheus-stack --versions | head -3
```

Update the `version:` fields in `platform/*/kustomization.yaml`. After the
first sync, Renovate takes over and opens the bump PRs for you.

> **The one invariant that will bite you:** the argo-cd chart version appears
> in *two* places — `CHART_VERSION` in `bootstrap/install.sh` and
> `targetRevision` in `clusters/prod/argocd.yaml`. They must match. If they
> drift, Argo CD's first self-sync changes its own version mid-bootstrap.

### 3. Fill in the TODOs

```bash
grep -rn "TODO\|example.com\|ORG" --exclude-dir=.git .
```

At minimum: your Argo CD hostname, the ACME contact email, and your secrets
provider in `platform/external-secrets/clustersecretstore.yaml`.

---

## Bootstrap

```bash
./bootstrap/install.sh
```

This renders the argo-cd chart, applies it, waits for readiness, then applies
`bootstrap/root-app.yaml` — the single Application that pulls in everything
else. Get the initial password and open the UI:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo

kubectl -n argocd port-forward svc/argocd-server 8080:80
```

Watch it converge:

```bash
kubectl -n argocd get applications -w
```

---

## How it fits together

```
bootstrap/root-app.yaml  ──▶  clusters/prod/
                                 ├── projects.yaml         AppProjects (the security boundary)
                                 ├── argocd.yaml           Argo CD manages itself
                                 ├── platform-appset.yaml  ──▶ platform/*/
                                 └── apps-appset.yaml      ──▶ apps/*/overlays/*/
```

Both ApplicationSets use a Git **files** generator over `config.yaml`, so each
component declares its own namespace, sync wave, and project. Adding a
component is a new directory plus a `config.yaml` — no edit to the generator.

### Sync waves

Infrastructure ordering is not optional; a `ClusterIssuer` applied before
cert-manager's CRD simply fails.

| Wave | Component | Why here |
|------|-----------|----------|
| -100 | AppProjects | Nothing can deploy without a project |
| -50  | Argo CD | Config changes must land before they're relied on |
| -40  | external-secrets | Everything downstream needs secrets |
| -30  | cert-manager | CRDs before ClusterIssuers (-25) |
| -20  | ingress-nginx | IngressClass before any Ingress |
| 0    | kube-prometheus-stack | ServiceMonitor CRDs |
| 0+   | applications | |

### Repo layout

```
bootstrap/    the one-time install and the root Application
clusters/     per-cluster entrypoints — copy prod/ to add a cluster
platform/     cluster infrastructure, one directory per component
apps/         workloads: base/ + overlays/<env>/
scripts/      set-repo, local render, diff preview
```

---

## Day-two operations

**Deploying an app change.** Merge a PR that changes the image tag in
`apps/<app>/overlays/<env>/kustomization.yaml`. That commit is the deploy
record.

**Promoting dev → prod.** Copy the digest already running in dev into the prod
overlay. A human reviews the diff. There is no separate promotion tool and no
mutable tag to chase.

**Adding a platform component.**

```
platform/my-thing/
├── config.yaml           name, namespace, syncWave
└── kustomization.yaml    helmCharts: or plain resources
```

Add its chart repo to `sourceRepos` in the `platform` AppProject, or the
Application will be rejected.

**Adding a cluster.** Copy `clusters/prod/` to `clusters/staging/`, change the
`destination.server`, register the cluster with `argocd cluster add`, and
apply a second root Application.

**Previewing a change locally.**

```bash
./scripts/render-all.sh          # render everything the way repo-server would
./scripts/diff.sh demo-app-prod  # what would actually change in the cluster
```

**Emergency: I need to stop Argo CD reverting my hotfix.** Don't disable
selfHeal globally. Either annotate the specific resource with
`argocd.argoproj.io/compare-options: IgnoreExtraneous`, or accept that the
correct move is a commit. The second option is almost always right — the
first hotfix that bypasses Git is how a cluster stops matching its repo.

---

## Deliberate choices, and when to revisit them

**`applicationsSync: create-update` on both ApplicationSets.** Generated
Applications are not deleted when the generator stops producing them. A
mistyped path should not be able to tear down the platform in one reconcile.
Switch to `create-delete` once you trust the pipeline — but know what you're
trading.

**External Secrets over Sealed Secrets.** Sealed Secrets' per-cluster
encryption key makes disaster recovery and multi-cluster promotion awkward:
the same manifest can't be applied to two clusters. See
`platform/external-secrets/README.md` for the SOPS + age alternative if you
want the repo self-contained.

**Kustomize for apps, Helm for third-party charts.** Helm's templating is
worth it for software you didn't write. For your own manifests, Kustomize
overlays give Argo CD cleaner diffs and no rendering surprises.

**Single Argo CD instance.** Fine here. A hub managing many remote clusters
is less overhead but concentrates blast radius and availability risk; for
multiple production tiers, per-cluster instances age better.

**`selfHeal: true` in production too.** Half the value of GitOps is drift
correction, and an environment where it's disabled is an environment where
Git is aspirational. Where runtime mutation is legitimate — HPA replicas,
injected sidecars — use `ignoreDifferences` instead (see the `apps`
ApplicationSet, which already handles the HPA case).

---

## Hardening checklist

Not done by the bootstrap. Work through these before calling the cluster
production-ready.

- [ ] Configure SSO (`configs.cm.oidc.config` in `bootstrap/argocd-values.yaml`)
- [ ] Set `admin.enabled: false` and delete `argocd-initial-admin-secret`
- [ ] Review the RBAC policy — `policy.default: role:readonly` is set, but the
      group mappings are placeholders
- [ ] Enable the Argo CD ingress (`server.ingress.enabled`) once cert-manager
      and ingress-nginx are healthy
- [ ] Add a Git webhook so syncs are event-driven rather than polling every 180s
- [ ] Provide the Slack token for notifications via External Secrets
- [ ] Turn on `redis-ha` and raise controller/server replicas for real HA
- [ ] Add NetworkPolicies for the `argocd` namespace
- [ ] Confirm `orphanedResources.warn` findings are empty — anything listed is
      drift that predates Argo CD
- [ ] Test disaster recovery: delete the cluster, recreate, run
      `bootstrap/install.sh`, verify convergence. If anything is missing, that
      gap is your real risk.
