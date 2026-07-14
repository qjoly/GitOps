# Onboarding: `Americano` — the first podman / Materia host in this GitOps

**Started:** 2026-07-14
**Scope:** new standalone host `Americano` (`sonarr.americano.thoughtless.eu`, `85.17.65.41`).
No impact on the `mocha` / `turing` Kubernetes clusters.
**Status:** Done. SSO live on sonarr/radarr, Overseerr installed + migrated, old instance
redirected, and the host's quadlets brought under Materia GitOps sourced from this repo.

## Why this one is different

`mocha` and `turing` are Talos Kubernetes clusters reconciled by **ArgoCD** from this repo.
`Americano` is **not a cluster**: it is a bare host running the media stack (sonarr, radarr,
overseerr, plex, prowlarr, deluge, …) as **podman quadlets**, fronted by a local **Traefik**
(docker provider reading the podman socket + a file provider for dynamic config).

Its GitOps engine is **[Materia](https://github.com/stryan/materia)** (GitOps for quadlets),
not ArgoCD. Materia clones a repo and expects `MANIFEST.toml` **at the repo root** — it has no
"source subdirectory" option. To still keep everything in `qjoly/gitops`, the human-readable
tree lives in [`americano/`](../../americano/) on `main`, and a GitHub Action republishes that
folder's contents to the **root of the `americano` branch**, which Materia consumes. See
[`americano/README.md`](../../americano/README.md) for the mechanics.

## What was done (three chunks)

### 1. Authentik SSO in front of sonarr / radarr

sonarr and radarr have no native SSO, so a **Proxy Provider in `forward_single` mode** was used
(the classic Proxy mode is impossible here: the embedded outpost runs on `mocha` and cannot reach
the app ports on this host).

- authentik (`mocha`): created 2 Proxy Providers + Applications (Sonarr, Radarr) and assigned
  them to the embedded outpost. Access **restricted to user `qjoly`** via a per-application
  PolicyBinding. Objects created imperatively via `ak shell` (consistent with the existing
  non-GitOps authentik config). Gotcha: creating a ProxyProvider through the ORM leaves
  `redirect_uris` empty → "mismatching redirect_uri"; fixed with `set_oauth_defaults()`.
- Traefik (Americano, file provider `/data/apps/traefik/config/static.yml`): a `forwardAuth`
  middleware to the mocha outpost + per-host `/outpost.goauthentik.io/` routers
  (`service authentik-outpost`, `passHostHeader: false`). The middleware is attached to the app
  routers via the quadlet label `traefik.http.routers.<app>.middlewares=authentik@file`.
- sonarr/radarr `config.xml`: `AuthenticationMethod` `Forms` → **`External`** (delegate auth to
  the proxy; the exporters keep working via their API key).
- **Central gotcha:** the mocha Traefik ingress **rewrites `X-Forwarded-Host`**, so the outpost
  saw `authentik.mocha…` and returned 404. Fixed in `mocha/system/traefik/app.yaml` by trusting
  the Americano egress IP: `ports.websecure.forwardedHeaders.trustedIPs: [85.17.65.41/32]`.

### 2. Overseerr — new install + migration off `headscale`

- Installed Overseerr as a quadlet (`docker.io/sctx/overseerr:latest`, config in
  `/data/apps/overseerr/config`) exposed at `https://overseerr.americano.thoughtless.eu`
  (wildcard `*.americano.thoughtless.eu` DNS → no DNS change needed).
- Migrated the full config/DB from the old instance on `headscale`
  (`/root/JellySeer/config`): both instances stopped for a consistent SQLite snapshot, streamed
  via `tar` through the operator's machine, restarted. Users, requests and Plex config carried
  over.
- Repointed the sonarr/radarr connections **from their public URLs to the internal container
  names** (`http://sonarr:8989`, `http://radarr:7878`) — the public URLs are now behind the SSO
  added in chunk 1, which would block Overseerr's API. Set `applicationUrl`.
- Old instance: replaced by a **redirect service**. On `headscale`'s Traefik file provider, a
  router on `Host(request.thoughtless.eu)` with `service noop@internal` + a `redirectRegex`
  middleware → `https://overseerr.americano.thoughtless.eu` (path + query preserved, HTTP 308).
  No container needed. Old Overseerr container left stopped.

### 3. Materia GitOps onboarding

- Discovered Materia was already installed but its **cron was broken**: the binary is at
  `/usr/local/bin/materia`, absent from cron's `PATH`, so `materia update` failed every 15 min
  (`env: 'materia': No such file or directory`). Nothing had been reconciling. Fixed with the
  absolute path.
- Repointed Materia's source from the standalone `quadlet.coffee.gitops` to **this repo**
  (`MATERIA_SOURCE__URL=github.com/qjoly/gitops`, `MATERIA_GIT__BRANCH=americano`).
- Created the `americano/` Materia tree (components `nginx`, `sonarr`, `radarr`, `overseerr`)
  and the publish workflow `.github/workflows/materia-americano.yaml`.
- Cutover: the previously hand-written flat quadlets
  (`/etc/containers/systemd/{sonarr,radarr,overseerr}.container`) were removed (backed up to
  `/root/quadlet-flat-backup/`) and `materia update` redeployed them as Materia-managed
  components under `/etc/containers/systemd/<comp>/` (each with a `.materia_managed` marker).
  `materia plan` now reports **"No changes made"**.

## Decisions

- **Not ArgoCD.** A podman host doesn't fit the cluster/ApplicationSet model; Materia is the
  right tool and was already bootstrapped on the box.
- **Folder on `main` + CI-published branch**, rather than a dedicated repo or an orphan branch
  edited by hand. Keeps the config in `qjoly/gitops`, readable and reviewable on `main`, while
  satisfying Materia's "manifest at root" requirement. Chosen by the user over a separate repo.
- **`Cleanup` stays off** in Materia: it only manages the four declared components; every other
  app on the host (plex, prowlarr, traefik, …) stays as a manual flat quadlet, untouched.
- **Host-key casing:** the folder and branch are lowercase `americano`, but `[Hosts.Americano]`
  in `MANIFEST.toml` and `attributes/Americano.toml` keep the capital `A` — Materia matches them
  against the real hostname (`Americano`); lowercasing them would break component selection.

## Follow-ups / notes

- The Americano host and its Traefik/authentik-side changes (except the mocha `trustedIPs`
  tweak) are **not** otherwise represented in git — they live on the box and are now, for the
  four onboarded apps, reproducible via Materia.
- A stale Radarr entry (`server937.seedhost.eu`) remains in Overseerr's settings from the old
  setup; it errors on sync and should be removed from the UI.

## Progress log

- 2026-07-14 — authentik SSO wired for sonarr/radarr (forward_single + Traefik forwardAuth),
  mocha `trustedIPs` fix committed & deployed, access restricted to `qjoly`. Verified end to end
  (302 → authentik, callback path 204).
- 2026-07-14 — Overseerr installed, DB migrated from headscale, sonarr/radarr repointed to
  internal names, old URL redirected (308).
- 2026-07-14 — Materia onboarding: `americano/` tree + publish workflow committed & pushed
  (branch `americano` produced by CI), Materia repointed to this repo, cron fixed, flat quadlets
  cut over to Materia-managed components. `materia plan` clean.
