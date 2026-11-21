# `Americano` — Materia GitOps

This folder holds the [Materia](https://github.com/stryan/materia) configuration for the
**`Americano`** host (`sonarr.americano.thoughtless.eu`, `85.17.65.41`).

Unlike the Kubernetes clusters (`mocha/`, `turing/`, `doppio/`, reconciled by ArgoCD), `Americano` is a
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
   push that touches it (one commit per change, on top of the branch history).
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
components = ["nginx", "sonarr", "radarr", "overseerr", "prowlarr"]
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

## Expose an app over NetBird

The `netbird` component runs the NetBird client on the host (host network mode).
It joins `netbird.mocha.thoughtless.eu` and gets an IP in `100.64.0.0/10`. Other
peers reach this host at that IP, for example `http://100.92.x.x:7171`.

One-time setup on the host (the key is never committed):

1. Store the setup key in a podman secret, from Vault on `mocha-corium`:

   ```
   mise run vault:kv get -field=americano_setup_key kv/netbird \
     | ssh root@test.americano.thoughtless.eu "podman secret create netbird-americano -"
   ```

   The key is the reusable non-ephemeral key `americano` in the NetBird
   dashboard (auto-group `americano`). Non-ephemeral plus the persisted
   `/var/lib/netbird` volume keep the peer and its NetBird IP stable across
   restarts. Rotate it by creating a new key and re-running step 1.

2. Allow the NetBird range only, on the app ports you expose. Edit
   `/etc/nftables-americano.nft` on the host (the port list is at the top of the
   file), then apply it:

   ```
   ssh root@test.americano.thoughtless.eu "nft -f /etc/nftables-americano.nft && systemctl enable --now nftables-americano"
   ```

3. Publish the app port on all interfaces instead of loopback, for example in
   `/etc/containers/systemd/agregarr.container`:

   ```
   PublishPort=0.0.0.0:7171:7171
   ```

   then `systemctl daemon-reload && systemctl restart agregarr`.

The NetBird `Default` policy already lets every peer talk to every peer, so no
access policy change is needed. The nftables table is the gate: it accepts
`100.64.0.0/10` on the listed ports and drops everyone else, so the port stays
closed on the public IP.

### Fixed NetBird URL for an app (example: `agregar.nb.mocha.thoughtless.eu`)

Agregarr is reachable at `https://agregar.nb.mocha.thoughtless.eu/` from any
NetBird peer. Three pieces make that work:

Agregarr's old public router (`agregarr.americano.thoughtless.eu`) is removed:
the app is only reachable via NetBird now.

1. A DNS record `agregar.nb.mocha.thoughtless.eu` (type A) in the NetBird zone
   `nb.mocha.thoughtless.eu`, pointing to Americano's NetBird IP. Peers do not
   use NetBird DNS today (no nameserver is assigned), so this record only helps
   if nameservers get enabled later.
2. A second traefik router on the app container (see the `agregarr-nb` labels
   in `/etc/containers/systemd/agregarr.container`): `Host(`agregar.nb.mocha.thoughtless.eu`)`
   on the `secure` entrypoint, TLS via the `letsencrypt` resolver (DNS-01
   Cloudflare, no `httpChallenge` in `traefik.yaml` anymore).
3. In `mocha/apps/netbird-jump/manifests/Corefile`, a dedicated server block for
   `agregar.nb.mocha.thoughtless.eu` pointing at the NetBird IP. This is the
   resolution path actually used by the jump SOCKS proxy and the Mac.

If the Americano peer ever re-registers with a new NetBird IP, update the IP in
all three places.

## Good to know

- Materia installs each component into its own directory
  `/etc/containers/systemd/<name>/` with a `.materia_managed` marker.
- **Cleanup is disabled**: Materia only touches the components listed above. Every other app on
  the host (plex, traefik, deluge, …) is a manual flat quadlet and is left alone. To
  bring one under GitOps, move it into a component here (and delete the old flat
  `/etc/containers/systemd/<name>.container`, or you get a duplicate unit).
- The host cron runs `materia update` every 15 min (uses the absolute binary path
  `/usr/local/bin/materia`).
- `sonarr` / `radarr` / `prowlarr` carry the label
  `traefik.http.routers.<app>.middlewares=authentik@file` — that is the Authentik SSO gate
  (forward-auth). Don't drop it when editing those quadlets.
