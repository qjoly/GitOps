# `Americano` — Materia GitOps

This folder holds the [Materia](https://github.com/stryan/materia) configuration for the
**`Americano`** host (`sonarr.americano.thoughtless.eu`, `85.17.65.41`).

Unlike `mocha/` and `turing/` (Talos Kubernetes clusters reconciled by ArgoCD), `Americano` is a
bare host running its stack as **podman quadlets**. Materia is its GitOps engine: it clones a
repo, figures out which components are assigned to the host, and renders the quadlets into
`/etc/containers/systemd/`.

## How Materia reads this (the branch trick)

Materia expects `MANIFEST.toml` **at the root of the cloned repo** — it has **no option to point
at a subdirectory**. This repo's root is already the Kubernetes GitOps tree, so we can't put the
manifest there.

So:

1. The readable, reviewable source of truth lives here in `americano/` on `main`.
2. The GitHub Action [`.github/workflows/materia-americano.yaml`](../.github/workflows/materia-americano.yaml)
   republishes the **contents of `americano/`** to the **root of the `americano` branch** on every
   push (force-pushed, single commit).
3. Materia on the host is pointed at this repo, branch `americano`:

   ```
   # /etc/materia/env
   MATERIA_SOURCE__KIND=git
   MATERIA_SOURCE__URL=https://github.com/qjoly/gitops
   MATERIA_GIT__BRANCH=americano
   MATERIA_ATTRIBUTES=file
   MATERIA_FILE__BASE_DIR=attributes
   ```

Edit files **here**, on `main`. Never edit the `americano` branch by hand — it is machine-generated.

## Layout

```
americano/
├── MANIFEST.toml              # which components run on which host
├── attributes/
│   └── Americano.toml         # host-specific attributes (matched to the hostname)
└── components/
    └── <name>/
        ├── MANIFEST.toml      # [[Services]] to (re)start when the component changes
        └── <name>.container   # the quadlet
```

`MANIFEST.toml`:

```toml
[Hosts.Americano]
components = ["nginx", "sonarr", "radarr", "overseerr"]
```

> **Casing matters.** The folder and branch are lowercase `americano`, but `[Hosts.Americano]`
> and `attributes/Americano.toml` keep the capital `A`: Materia matches them against the host's
> real hostname (`Americano`). Lowercasing them would silently deselect every component.

## Add or change a component

1. Create `components/<name>/<name>.container` (a normal quadlet) and a
   `components/<name>/MANIFEST.toml`:

   ```toml
   [[Services]]
   Service = "<name>.service"
   ```

2. Add `"<name>"` to `components` in the root `MANIFEST.toml`.
3. Commit & push to `main`. The Action publishes the `americano` branch; within 15 min the host's
   cron runs `materia update`, or run it now on the host:

   ```
   env $(cat /etc/materia/env | xargs) /usr/local/bin/materia update
   ```

   Preview without applying: same command with `plan` instead of `update`.

## Good to know

- Materia installs each component into its own directory
  `/etc/containers/systemd/<name>/` with a `.materia_managed` marker.
- **Cleanup is disabled**: Materia only touches the components listed above. Every other app on
  the host (plex, prowlarr, traefik, deluge, …) is a manual flat quadlet and is left alone. To
  bring one under GitOps, move it into a component here (and delete the old flat
  `/etc/containers/systemd/<name>.container`, or you get a duplicate unit).
- The host cron runs `materia update` every 15 min (uses the absolute binary path
  `/usr/local/bin/materia`).
- `sonarr` / `radarr` carry the label
  `traefik.http.routers.<app>.middlewares=authentik@file` — that is the Authentik SSO gate
  (forward-auth). Don't drop it when editing those quadlets.
