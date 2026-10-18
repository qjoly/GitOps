# Secret Management

Secrets never live in this repository. They are stored in a Vault on each
cluster, and the External Secrets operator copies them into Kubernetes Secrets.

## Vault

Every cluster (mocha, turing, doppio) runs its own Vault — OpenBao, deployed by
the [bank-vaults](https://bank-vaults.dev) operator — in the `bank-vaults`
namespace. The `Vault` custom resource is in `<cluster>/system/bank-vaults/vault/vault.yaml`.

The operator handles what used to be manual:

- **Init and unseal.** It initialises Vault with 5 key shares (threshold 3) and
  stores them, along with the root token, in the `vault-unseal-keys` Secret of
  the `bank-vaults` namespace. A restarted pod is unsealed automatically.
- **Configuration.** The `externalConfig` block of the CR creates the `kv` KV v2
  engine, a read-only `reader` policy on `kv/*`, and a Kubernetes auth role
  `default` bound to that policy.
- **TLS.** Vault listens on HTTPS with a self-signed CA, published in the
  `vault-tls` Secret.

| Key in `vault-unseal-keys` | Content |
|---|---|
| `vault-root` | Root token |
| `vault-unseal-0` … `vault-unseal-4` | Unseal key shares |

### mise tasks

The tasks in `mise.toml` read the token and keys from that Secret and run
`vault` inside the Vault pod. They target `$VAULT_CONTEXT`, or the current
kubectl context.

```bash
export VAULT_CONTEXT=mocha-corium

mise run vault:status                          # seal status of every Vault pod
mise run vault:unseal                          # unseal pods the operator left sealed

mise run vault:kv list kv/
mise run vault:kv get kv/rmfakecloud
mise run vault:kv get -field=jwt_secret kv/rmfakecloud
mise run vault:kv put kv/foo user=admin password="$(openssl rand -hex 24)"
mise run vault:kv patch kv/foo password=-      # value read from stdin
```

`vault:kv` passes its arguments straight to `vault kv`, so any subcommand works
(`metadata delete`, `-format=json`, …). Only Vault's output goes to stdout,
which makes it safe to pipe into `jq`.

## External Secrets

The External Secrets operator reads Vault through a single `ClusterSecretStore`,
`vault-backend` (`<cluster>/system/external-secret/cluster-store.yaml`). It
authenticates with the Kubernetes auth method — no token is stored anywhere —
so it can only read, through the `reader` policy.

An app declares an `ExternalSecret` that points at a path under `kv/`:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: rmfakecloud
spec:
  refreshInterval: "1h"
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: rmfakecloud
    creationPolicy: Owner
  data:
    - secretKey: jwt_secret
      remoteRef:
        key: rmfakecloud        # kv/rmfakecloud
        property: jwt_secret
```

The workflow for a new secret:

1. Write the value: `mise run vault:kv put kv/<app> key="$(openssl rand -hex 24)"`
2. Commit only the `ExternalSecret`, never the value.
3. Force a resync if needed: `kubectl annotate externalsecret <name> force-sync=$(date +%s) --overwrite`
