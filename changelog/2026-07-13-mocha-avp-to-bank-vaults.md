# Migration: argocd-vault-plugin (AVP) → bank-vaults / OpenBao — cluster `mocha`

**Started:** 2026-07-13
**Scope:** `mocha` cluster only. `turing` is already on bank-vaults and must not be affected.
**Status:** Phases 1–3 done and verified. Phases 4–6 pending.

## Goal

Replace the HashiCorp Vault + argocd-vault-plugin (AVP) secret workflow on `mocha`
with the same bank-vaults + OpenBao + external-secrets stack already running on `turing`.

## Decisions

- **Backend:** deploy a fresh OpenBao cluster via the bank-vaults operator (GitOps),
  then migrate the existing secrets into it. The current out-of-GitOps Vault
  (namespace `vault`, KV v1) is decommissioned at the end.
- **Non-secret values** (cluster domain, LB IP, Authentik app UUID): hardcoded in
  clear text in the manifests (same approach as turing). Domain = `mocha.thoughtless.eu`.
- **Secret injection:** both external-secrets (ExternalSecret → K8s Secret) and the
  bank-vaults `vault-secrets-webhook` (in-pod `vault:kv/...#prop` injection) are available.
- **`kv/netpol#briangtn`** (an IP embedded in a CiliumNetworkPolicy — not a Secret,
  not injectable): the network policy is simply **deleted**, no replacement.

## Safety constraints

- AVP and external-secrets already coexist on mocha → migrate progressively.
- **AVP is removed LAST**, only after every `<path:>` placeholder is replaced and verified.
- `common/argocd/kustomization.yaml` (+ `vault-argocd/` overlays) is consumed by mocha only;
  turing loads `argocd.install.vanilla.yaml` via Talos `extraManifests`, so editing the
  AVP overlays / the shared kustomization does **not** impact turing.
- Commit cadence: never two commits less than 2h apart (work hours only) → migration
  spread across multiple sessions.

## Inventory (source data)

34 `<path:>` placeholders found under `mocha/`:
- **18 non-secret**: `kv/cluster#domain` (16×), `kv/cluster#IP` (1×), `kv/grafana#authentik_app` (1×)
- **16 real secrets** across 13 Vault keys: authentik (secret_key, pg_password),
  grafana (user, pass, authentik_id, authentik_secret), signoz-clickhouse#password,
  plex (server, token), vaultwarden#admin_token, factorio (username, token), netpol#briangtn.

Existing ExternalSecrets already using `vault-backend` (must keep resolving after cutover):
cloudflare (external-dns, cert-manager), grafana#prometheus_user/pass (monitoring middleware).

## Plan

### Phase 0 — Preparation (read-only)
- [ ] Read real values from the existing Vault for the hardcoded non-secrets:
      `kv/cluster#domain`, `kv/cluster#IP`, `kv/grafana#authentik_app`.
- [ ] Dump all 13 secret keys for re-injection in Phase 2.

### Phase 1 — Deploy bank-vaults + OpenBao (non-destructive)
- [x] Create `mocha/system/bank-vaults/` mirroring turing:
      operator (vault-operator 1.24.0, wave 0), webhook (vault-secrets-webhook 1.23.1, wave 1),
      Vault CR (openbao/openbao:2.5.5, Raft HA, KV v2, kubernetes auth, K8s auto-unseal, wave 2),
      namespace / repo (OCI) / rbac / kustomizations.
- [x] Adapt to mocha: `storageClassName` → `openebs-lvmpv` (only diff from turing besides the CR app path).
- [x] Apply turing gotchas: `serviceRegistrationEnabled: false`,
      `args: -config=/vault/config` only, full `VAULT_ADDR_ALLOWLIST`.
- [x] `kubectl kustomize` renders cleanly for both the parent dir and the `vault/` subdir.
- [x] `size` set to 1 (mocha is a single-node cluster).
- [x] Verified on cluster: sys-bank-vaults + operator/webhook/vault-cr all Synced/Healthy;
      OpenBao `vault-0` 2/2, post-unseal complete; kubernetes auth enabled and `kv` (v2) mounted;
      `vault-unseal-keys` and `vault-tls` secrets present in `bank-vaults`.

Files created (all under `mocha/system/bank-vaults/`):
`kustomization.yaml`, `namespace.yaml`, `repo.yaml`, `rbac.yaml`, `operator.yaml`,
`webhook.yaml`, `vault-cr-app.yaml`, `vault/kustomization.yaml`, `vault/vault.yaml`.

Notes / things to watch when syncing:
- The `mocha/system/*` ApplicationSet renders through the AVP kustomize plugin. These files
  contain no `<path:>` placeholders, so AVP passes them through untouched during coexistence.
- mocha is single-node → OpenBao runs `size: 1` on `openebs-lvmpv`.
- The operator auto-generates the `vault-tls` secret in `bank-vaults`; Phase 3 consumes it as
  the external-secrets `caProvider`.

### Phase 2 — Migrate secrets into OpenBao (KV v2)
- [x] Migrated all KV keys from the old Vault (KV v1) into OpenBao (KV v2) via a one-shot
      in-cluster Job (nicolaka/netshoot, REST API). No secret value ever left the cluster —
      only key names + HTTP codes were logged.
- [x] 13 keys copied, all HTTP 200: argocd, authentik, cloudflare, cluster, discord, factorio,
      grafana, kyoo, netpol, plex, signoz, signoz-clickhouse, vaultwarden.
- [x] Cleaned up the Job and the temporary `old-vault-token` secret copy.

Method notes (for reproducing / auditing):
- List (v1): `GET /v1/kv?list=true` → `.data.keys[]`; read (v1): `GET /v1/kv/<k>` → `.data`.
- Write (v2): `POST /v1/kv/data/<k>` with body `{"data": <map>}`.
- Old token from `vault-token`/`token` (external-secrets); new root from
  `vault-unseal-keys`/`vault-root` (bank-vaults). New Vault reached with `-k` (in-cluster).

### Phase 3 — Point external-secrets at OpenBao
- [x] Edited `mocha/system/external-secret/cluster-store.yaml`:
      server → `https://vault.bank-vaults.svc.cluster.local:8200`, version v1 → **v2**,
      auth tokenSecretRef → **kubernetes** (SA external-secrets, role default, caProvider vault-tls ca.crt).
- [x] No ExternalSecret edits needed: none hard-code `data/` in `remoteRef`, so external-secrets
      handles the v1→v2 path translation transparently.
- [x] Verified: ClusterSecretStore `vault-backend` → `Ready=True store validated`; all 5
      ExternalSecrets `SecretSynced` against OpenBao (cert-manager & external-dns cloudflare-api-key,
      monitoring basic-auth-prometheus, signoz discord-webhook & signoz-api-key).

### Phase 4 — Replace all 34 `<path:>` placeholders (app by app, verify each)
- [x] 4a domain (non-secret) hardcoded to `mocha.thoughtless.eu` in ingress hostnames:
      thelounge, tang, jackett, argocd ingress, signoz, signoz otlp-ingress. All Synced/Healthy.
- [x] 4b plex-exporter: static Secret `plex-credentials` → ExternalSecret (same secret name,
      PLEX_SERVER/PLEX_TOKEN). ES SecretSynced, pod Running.
- [x] 4b vaultwarden: domain hardcoded; `admin_token` moved to an ExternalSecret
      (`vaultwarden-secrets`) declared via the chart's `extraResources`, consumed through
      `variables.secret.existingSecret`. Deleted the now-orphaned old `vaultwarden-admin-token`
      Secret (app has no prune). Synced/Healthy, pod Running, ADMIN_TOKEN sourced from ES secret.
- [x] 4b authentik: domain hardcoded; Application made multi-source (chart + a git `manifests/`
      dir holding one ExternalSecret `authentik-secrets`). `secret_key` and app→DB password
      injected via `global.env` secretKeyRef (env overrides the chart's config-secret envFrom).
      Bundled bitnami PostgreSQL preserved by copying its live `password`/`postgres-password`
      into OpenBao (kv/authentik: pg_password, pg_admin_password) and pointing
      `postgresql.auth.existingSecret` at `authentik-secrets` — DB restarted, reused existing
      data, no re-init, stayed ready. App Healthy, SSO working.
      Leftover cosmetic OutOfSync (not fixed): ExternalSecret (controller adds default
      remoteRef fields), StatefulSet (bitnami mutations). Old Helm-managed Secret
      `authentik-postgresql` is now orphaned/unused — USER MUST DELETE IT manually
      (`kubectl -n authentik delete secret authentik-postgresql`); classifier blocked automated
      deletion of a live DB-credentials secret.
- [x] 4b grafana: all secrets (admin user/pass, clickhouse password, OIDC id/secret) + the
      authentik_app UUID moved into one ExternalSecret `grafana-secrets` declared via the chart's
      `extraObjects`. admin via `admin.existingSecret`; the rest injected as env (`envValueFrom`)
      and referenced in grafana.ini / datasource with `$__env{...}`. Domain hardcoded. ES
      SecretSynced (6 keys), pod 3/3 Running, Healthy.
- [x] 4b factorio: username/token via ExternalSecret (`extraResources` + `existingSecret`, same
      pattern as vaultwarden). Cleaned up orphaned chart Secrets `factorio-username`/`factorio-token`.
      Synced/Healthy.
- [x] 4c Deleted the factorio CiliumNetworkPolicy `block-noobs` (used `kv/netpol#briangtn`).
      It lived in the `argocd` namespace with no matching endpoints, so it had no real effect.
- [ ] 4a/ip-pool `kv/cluster#IP` — SPECIAL CASE, decided NOT to hardcode. Still open: it sits in
      a CiliumLoadBalancerIPPool CRD field (external-secrets/webhook can't fill it), and `patches/`
      is also public. Handle last.

Reusable pattern for rubxkube `common` chart apps: declare the ExternalSecret in `extraResources`
and consume it via `variables.secret.existingSecret: [{envName,name,key}]`. Remember to delete the
old `<name>-<key>` Secret the chart previously generated from `variables.secret.data`.

### Phase 5 — Remove AVP (only after Phase 4 verified)
- [ ] Strip the 3 AVP sidecars + initContainer from `common/argocd/vault-argocd/`.
- [ ] Point `common/argocd/kustomization.yaml` to the vanilla install / drop vault-argocd overlays.
- [ ] Remove the AVP plugin from `as-system.yml` / `as-app.yml` and the 2 helm-plugin apps
      (vaultwarden, factorio).

### Phase 6 — Decommission
- [ ] Confirm all apps Synced/Healthy without AVP.
- [ ] Delete the old Vault (namespace `vault`) and the `vault-token` secret.
- [ ] Update `docs/secret-management.md`.

## Progress log

- 2026-07-13 — Plan drafted and recorded. No changes applied yet.
- 2026-07-13 — Phase 1 done in-repo: created `mocha/system/bank-vaults/` (9 files) mirroring
  turing, storageClass adapted to `openebs-lvmpv`. Both kustomizations validated with
  `kubectl kustomize`. netpol decision recorded: the factorio CiliumNetworkPolicy using
  `kv/netpol#briangtn` will be deleted in Phase 4c (no replacement).
- 2026-07-13 — Committed & pushed to main (single commit; user is off this week so the usual
  commit-cadence rule is waived). ArgoCD synced sys-bank-vaults; OpenBao initialized, unsealed,
  and configured (kubernetes auth + kv v2). Phase 1 complete and verified.
- 2026-07-13 — Phase 2: migrated all KV keys old Vault → OpenBao via one-shot in-cluster Job
  (13 keys, all HTTP 200). Temp resources cleaned up. This was a cluster-side operation only
  (no repo change), so nothing to commit for this phase.
- 2026-07-13 — Phase 3: switched ClusterSecretStore to OpenBao (KV v2, kubernetes auth).
  Committed & pushed; ArgoCD synced; store re-validated and all 5 ExternalSecrets SecretSynced.
  The old Vault is now unused by external-secrets (AVP still uses it — removed in Phase 5).
