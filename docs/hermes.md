# Hermes on mocha

Hermes Agent runs as one pod in the `hermes-carolyn` namespace, deployed from
[`mocha/apps/hermes-carolyn/manifests/`](https://github.com/qjoly/GitOps/tree/main/mocha/apps/hermes-carolyn/manifests)
by ArgoCD. This page is the map: what runs in the pod, which path survives a
restart, where the credentials come from, and how the agent reaches GitHub and
the sandboxes.

The manifests are the source of truth. Read this page to know *where to look*,
then read the manifest before changing behaviour.

## One pod, many containers

Everything below runs in a single pod, so `127.0.0.1` works between them and
nothing talks to a Service except Traefik.

| Container | Role | Reached by |
|---|---|---|
| `hermes-carolyn` | the agent: gateway, Discord platform, kanban dispatcher | nothing inbound |
| `webui` | browser UI (`hermes-webui`) | Traefik on 8787 |
| `github-mcp` | GitHub API tools for the agent | agent on 8082 |
| `email-mcp` | reads the mailboxes, read-only | agent on 8080 |
| `calendar-mcp` | Google Calendar, read/write | agent on 8083 |
| `grafana-mcp` | Grafana on mocha, read-only (`--disable-write`) | agent on 8084 |
| `browser` | headless Chromium exposing CDP | agent on 9222 |
| `netbird` | WireGuard peer in netstack mode | agent through a SOCKS5 on 1080 |

The agent only ever reaches the MCP servers over loopback. `github-mcp` and
NetBird's socket bind on all interfaces, but
[`ciliumnetworkpolicy.yaml`](https://github.com/qjoly/GitOps/blob/main/mocha/apps/hermes-carolyn/manifests/ciliumnetworkpolicy.yaml)
makes the namespace default-deny ingress, so only Traefik (8787) and the
kubelet readiness probe get in. Same policy means "no egress section": outbound
traffic is open on purpose, the agent needs the internet.

## Init containers: what gets seeded where

Four init containers run before anything else. Each one is the single writer of
its target, so its repair is re-applied on every pod start.

| Container | Writes | Semantics |
|---|---|---|
| `seed-config` | `/opt/data/config.yaml` | **never overwrites** (`test -f … \|\| cp`) |
| `seed-calendar-creds` | the calendar MCP credential file in an `emptyDir` | overwrites, mode 600 |
| `seed-agent-src` | the agent source into an `emptyDir` shared with `webui` | copies from the image, then repairs two image defects |
| `install-sbx` | `sbx`, `kubectl`, `jq`, `arr.sh`, SSH material, the skills, and the `mistral-image` plugin | overwrites |

The seed-versus-overwrite split matters: a committed change to `config.yaml` or
`SOUL.md` does **not** reach a running pod, because the file already exists on
the volume. To apply one, delete the file on the PVC and restart. Everything
else — skills, `sbx`, `arr` — is replaced at every start, so a committed fix
wins immediately.

`seed-agent-src` deserves a warning: it repairs the image it copies. The
bundled `.venv` is built for Python 3.14 and the `install-stamp.json` bakes a
path that does not exist in the copy; both break the `webui` container, which
discovers the agent at `$HERMES_HOME/hermes-agent`. Do not delete those repair
lines without a replacement.

## Storage

One PVC, `hermes-carolyn-data`, mounted at **two paths**:

- `/opt/data` in `hermes-carolyn` — this is `HERMES_HOME`;
- `/workspace` in both `hermes-carolyn` and `webui`;
- `/home/hermeswebui/.hermes` in `webui`.

`/workspace` and `HERMES_HOME` are the same volume, which is why a repo cloned
by the agent shows up at `/workspace/<repo>` in the webui. Anything written
outside `/opt/data` and `/workspace` — an `emptyDir` — is gone on restart.

## Credentials

No secret lives in this repository. The
[`hermes-carolyn` ExternalSecret](https://github.com/qjoly/GitOps/blob/main/mocha/apps/hermes-carolyn/manifests/externalsecret.yaml)
maps keys from `kv/hermes-carolyn` in the cluster Vault (OpenBao) into the
`hermes-carolyn` Secret, which the containers read with `secretKeyRef`.

| Key in `kv/hermes-carolyn` | Used for |
|---|---|
| `github_token` | the `github-mcp` sidecar |
| `github_bot_token` | git and `gh` run by the agent (see below) |
| `mistral_api_key` | the model |
| `bot_token`, `allowed_users` | Discord |
| `hass_token` | Home Assistant MCP |
| `mail_password`, `mail_password_quentinj` | `email-mcp` |
| `sonarr_api_key`, `radarr_api_key`, `prowlarr_api_key`, `deluge_password` | `arr.sh` |
| `netbird_setup_key` | the NetBird peer |
| `grafana_token` | `grafana-mcp` |
| `webui_password` | the webui login |

A missing key is a **CrashLoop**, not a degraded start: `secretKeyRef` fails
the container. When you add a key to the ExternalSecret, add it to Vault in the
same change.

## The two GitHub identities

There are two tokens, and they are not interchangeable.

**`github_token`** authenticates the agent to the GitHub API through the
`github-mcp` sidecar. The [MCP config](https://github.com/qjoly/GitOps/blob/main/mocha/apps/hermes-carolyn/manifests/configmap.yaml)
sends it as `Authorization: Bearer ${GITHUB_TOKEN}`; the server runs with the
`repos,issues,pull_requests,search` toolsets.

**`github_bot_token`** belongs to a separate bot account, `unetassedecafe`, and is
what `git` and `gh` use when the agent publishes work. It is wired as `GH_TOKEN`
plus a git credential helper through `GIT_CONFIG_*` environment variables — not in
`.git/config`, because `sbx push` copies `.git` into the sandbox. The bot is a
collaborator with `read` on this repository: it pushes a branch to its own fork
(`unetassedecafe/GitOps`) and opens a pull request from there.

Two rules follow, and they are the ones that get broken:

- **No token in a sandbox.** The sandbox template rejects injected env vars, and
  nothing needs one: `mise install` resolves tools through
  `mise-versions.jdx.dev`, not the GitHub API (verified with `mise token github`
  reporting *none* and all four tools installing). Build and test in the
  sandbox; commit and push from the pod.
- **Never push to `main`.** The bot's access is read-only on the upstream repo,
  so a direct push fails. Open a PR.

## Sandboxes

`sbx` (in
[`sbx-configmap.yaml`](https://github.com/qjoly/GitOps/blob/main/mocha/apps/hermes-carolyn/manifests/sbx-configmap.yaml))
drives disposable gVisor pods in the `sandboxes` namespace. The checkout is
copied in, work happens there, and the result comes back as a git patch:

```bash
n=$(sbx up)
sbx push "$n" .
sbx exec "$n" -- bash -c 'mise install && make test'
sbx diff "$n" | git apply
sbx down "$n"
```

The pod reaches the API server with its own service account, which has a
namespace-scoped Role in `sandboxes` only. The sandbox itself has no service
account token, no cluster network, and no credentials. See
[Sandboxes](sandboxes.md) for the template and the warm pool.

## Talking to the agent

Two surfaces, both on the NetBird-only `*.nb.mocha.thoughtless.eu` zone, so
neither is reachable from the public internet:

- `hermes-carolyn.nb.mocha.thoughtless.eu` — the webui, password login
  (`HERMES_WEBUI_PASSWORD`, from Vault).
- `hermes-carolyn-gw.nb.mocha.thoughtless.eu` — the gateway, for the Hermes
  Desktop app and the JSON-RPC/WebSocket backend, with basic auth.

Discord is a platform, not a surface: the agent answers there and auto-threads,
mention required.

## The Bot Desktop screen

The Hermes Desktop "Screen" pane gives the agent its own Xfce desktop (TigerVNC
`Xvnc` on a Unix socket under `/opt/data/bot-desktop/`), which `computer_use`
drives and a human can take over. It needs system packages that the upstream
image does not ship, and its "Install on host" button cannot add them: the
gateway runs as the unprivileged `hermes` user and there is no `sudo`.

So `hermes-carolyn` and `seed-agent-src` run
`ghcr.io/qjoly/hermes-agent-desktop`, the upstream image plus those packages,
built from
[`image/Dockerfile`](https://github.com/qjoly/GitOps/blob/main/mocha/apps/hermes-carolyn/image/Dockerfile)
by the `hermes-agent-desktop-image` workflow and tagged like its base. Bumping
Hermes is two steps: bump the `FROM` line (the workflow builds the new tag on
the PR), then the two `image:` lines in the Deployment. Keep both containers
on the same tag, since the webui runs the agent source copied by
`seed-agent-src`.

From a shell in the pod: `hermes computer-use screen status|start|stop`.

## Changing it

1. Edit the manifests in `mocha/apps/hermes-carolyn/manifests/`, never the pod.
   `selfHeal: true` reverts a manual `kubectl edit`.
2. Render in a sandbox — `kubectl kustomize` is the check that the change still
   parses and still produces every document.
3. If the change needs a new Vault key, write it first, then open the PR.
4. Open a PR. ArgoCD syncs it after merge; a seeding change may need the file
   deleted on the PVC to take effect.
