# Secrets

## Why this and not Sealed Secrets

Sealed Secrets works, but the encryption key is per-cluster. That makes
disaster recovery and multi-cluster promotion awkward: the same manifest
cannot be applied to two clusters, and losing the key means re-sealing
everything. External Secrets keeps the source of truth in a system that
already has audit logging, rotation, and access control.

## The alternative worth considering: SOPS + age

If you have no external secret store and want the repo self-contained, use
SOPS with age keys and the `argocd-vault-plugin` or a kustomize SOPS
generator. Encrypted values *are* committed; only the age private key lives
in the cluster. Simpler to operate, weaker rotation story.

## Usage

Reference an external secret from an app overlay:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: demo-app-db
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: default
    kind: ClusterSecretStore
  target:
    name: demo-app-db          # the k8s Secret that gets created
  data:
    - secretKey: password
      remoteRef:
        key: prod/demo-app/db
        property: password
```

The generated Secret is not tracked by Argo CD, so `prune` will not remove
it and diffs stay clean.
