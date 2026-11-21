# NetBird logins made durable, and the Mac Mini provisioned with a setup key

**Started:** 2026-11-21
**Scope:** NetBird account/peer login expiration disabled via the management
API, reusable setup key `matcha` in NetBird, `kv/netbird` `mac_setup_key` in
Vault, new `mise run nb:peer` task on macOS.

## Why

Two things made `Matcha.local` show as disconnected with a warning and force a
fresh authentik login every time:

- The account setting `peer_login_expiration_enabled` was `true` with
  `peer_login_expiration = 86400` (24 h). Every SSO peer (the Mac's desktop
  client logs in through the authentik OIDC provider) expired after 24 h; while
  expired it was disconnected and the client had to re-login in a browser, i.e.
  re-authenticate on authentik.
- A sleeping Mac Mini drops its WireGuard connection, so the peer read
  "last seen … ago" until it woke.

## SSO made durable (the actual fix for the re-logins)

- `PUT /api/accounts/dbun6tt27a40009lvbgg` with
  `settings.peer_login_expiration_enabled = false`: SSO peer logins now never
  expire. The helm chart has no value for this (checked `helm show values
  netbird@1.9.0`); the setting lives in the management sqlite DB
  (`persistentVolume` on `openebs-lvmpv`), so it survives upgrades and ArgoCD
  does not revert it. Re-apply it only if the datastore is ever wiped.
- Per-peer `login_expiration_enabled = false` on the existing SSO peers
  (`Matcha.local`, `iPhone`) via `PUT /api/peers/<id>`. The iPhone showed
  `login_expired = true` until its next connection; with the flag off, its
  stored login is accepted again and at most one re-login is needed.

## Mac Mini provisioned with a setup key (no SSO, no sleep drop)

## What was done

- Setup key **`matcha`**: reusable, **non-ephemeral** (the peer is not deleted
  when the Mac sleeps), `usage_limit = 0`, auto-group `users`. Created through
  the management API with the `kv/netbird` `operator_api_key` PAT:

  ```bash
  curl -X POST -H "Authorization: Token $PAT" -H "Content-Type: application/json" \
    -d '{"name":"matcha","type":"reusable","ephemeral":false,"usage_limit":0,"auto_groups":["<users-group-id>"]}' \
    https://netbird.mocha.thoughtless.eu/api/setup-keys
  ```

- The key is stored as `kv/netbird` **`mac_setup_key`** (never committed):

  ```bash
  mise run vault:kv patch kv/netbird mac_setup_key=<key from the API response>
  ```

  (`kv patch`, not `kv put`: on this OpenBao, `put` replaces the whole data of
  the path and would drop the other `kv/netbird` keys.)

- **`mise run nb:peer`** (one-time, sudo, on the Mac): reads `mac_setup_key`
  from Vault, writes it to `/etc/netbird-matcha.key` (chmod 600, never in the
  plist or git), installs a LaunchDaemon `eu.thoughtless.netbird-matcha` that
  runs `netbird up --management-url https://netbird.mocha.thoughtless.eu
  --setup-key …` in a loop, and sets `pmset -a womp 1` + `sleep 0 disksleep 0`
  so the Mini stays awake and the peer stays connected. `nb:teardown` now
  removes this daemon too.

Setup-key peers have no SSO user, so the 24 h login expiration does not apply to
them: no browser, no authentik, ever.

## Use it on the Mac Mini

1. `mise install && mise run nb:peer` (sudo prompts).
2. Quit the NetBird desktop app if it was running (it holds the SSO session).
3. Delete the old SSO peer `Matcha.local` in the NetBird dashboard (Peers), or:

   ```bash
   PAT="$(mise run -q vault:kv get -field=operator_api_key kv/netbird)"
   curl -X DELETE -H "Authorization: Token $PAT" \
     https://netbird.mocha.thoughtless.eu/api/peers/dc0093t27a4000cpo9cg
   ```

4. Check: `sudo netbird status`, and the peer in the dashboard is connected with
   no warning. The Mac gets a new NetBird IP (nothing in this repo referenced
   the old `100.92.44.4`).

## Rotate the key

Revoke `matcha` in the dashboard (or `DELETE /api/setup-keys/<id>`), create a
new one, `mise run vault:kv patch kv/netbird mac_setup_key=<new>`, then
re-run `mise run nb:peer` on the Mac (it rewrites `/etc/netbird-matcha.key` and
restarts the daemon).

## Left unchanged

Nothing on the authentik side: the NetBird OIDC provider and its authentik
sessions were not touched. The peer login expiration was the cause of the
repeated authentik logins; with it disabled, SSO peers log in once and stay.
