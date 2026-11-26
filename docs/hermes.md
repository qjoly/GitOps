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
| `hermes-carolyn` | the agent: gateway, Discord platform, kanban dispatcher, and its Bot Desktop screen + headed Chromium | nothing inbound |
| `webui` | browser UI (`hermes-webui`) | Traefik on 8787 |
| `github-mcp` | GitHub API tools for the agent | agent on 8082 |
| `email-mcp` | reads the mailboxes, read-only | agent on 8080 |
| `calendar-mcp` | Google Calendar, read/write | agent on 8083 |
| `grafana-mcp` | Grafana on mocha, read-only (`--disable-write`) | agent on 8084 |
| `netbird` | WireGuard peer in netstack mode | agent through a SOCKS5 on 1080 |

The agent only ever reaches the MCP servers over loopback. `github-mcp` and
NetBird's socket bind on all interfaces, but
[`ciliumnetworkpolicy.yaml`](https://github.com/qjoly/GitOps/blob/main/mocha/apps/hermes-carolyn/manifests/ciliumnetworkpolicy.yaml)
makes the namespace default-deny ingress, so only Traefik (8787) and the
kubelet readiness probe get in. Same policy means "no egress section": outbound
traffic is open on purpose, the agent needs the internet.

## Init containers: what gets seeded where

Five init containers run before anything else. Each one is the single writer of
its target, so its repair is re-applied on every pod start.

| Container | Writes | Semantics |
|---|---|---|
| `seed-config` | `/opt/data/config.yaml` | **never overwrites** (`test -f … \|\| cp`) |
| `seed-calendar-creds` | the calendar MCP credential file in an `emptyDir` | overwrites, mode 600 |
| `seed-agent-src` | the agent source into an `emptyDir` shared with `webui` | copies from the image, then repairs two image defects |
| `install-cua-driver` | the pinned `cua-driver` (computer_use) under `/opt/data/tools` | no-op when present, repairs after a bump; not fatal |
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
| `github_bot_token` | the only GitHub credential: `github-mcp` sidecar **and** git/`gh` (see below) |
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

## The one GitHub identity

There is a single GitHub token, `github_bot_token`, belonging to the bot
account **unetassedecafe** — the `qjoly` account is deliberately not reachable
from Hermes (`github_token` no longer exists in the ExternalSecret). It is used
both by the `github-mcp` sidecar (`GITHUB_PERSONAL_ACCESS_TOKEN`, with the MCP
config sending `Authorization: Bearer ${GH_TOKEN}`; the server runs with the
`repos,issues,pull_requests,search` toolsets) and by `git`/`gh` run by the agent,
wired as `GH_TOKEN` plus a git credential helper through `GIT_CONFIG_*`
environment variables — not in `.git/config`, because `sbx push` copies `.git`
into the sandbox. The bot is a collaborator with `read` on this repository: it
pushes a branch to its own fork (`unetassedecafe/GitOps`) and opens a pull
request from there.

The token is also given to the VMs, file-only, so `git`/`gh` work in-session:

- **kube-sandbox terminal backend**: `terminal.kube_sandbox_git_user` in the
  [MCP config](https://github.com/qjoly/GitOps/blob/main/mocha/apps/hermes-carolyn/manifests/configmap.yaml)
  plus the pod's `KUBE_SANDBOX_GIT_TOKEN` env make the plugin write
  `/root/.git-credentials` as `https://unetassedecafe:$TOKEN@github.com`
  (mode 0600) and set `credential.helper=store` inside the micro-VM at claim
  time — file-only, never in the sandbox environment. (Not
  `kube_sandbox_secret_files`: it writes the raw env value, but credential
  store expects a full URL and would leave the helper unset.)
- **`sbx` sandboxes**: `sbx up` seeds the same `/root/.git-credentials` from the
  pod's `GH_TOKEN` over the exec stdin (never argv, never under `/work`, so it
  is not copied back by `sbx diff`).

Rules that follow, and are the ones that get broken:

- **No secret other than the bot token in a sandbox.** The sandbox template
  rejects injected env vars (`envVarsInjectionPolicy: Disallowed`), so the token
  always lands as a file, never in the env. Never pass a kubeconfig or any other
  secret in: use `exec` stdin. `mise install` resolves tools through
  `mise-versions.jdx.dev`, not the GitHub API (verified with `mise token github`
  reporting *none* and all four tools installing).
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
namespace-scoped Role in `sandboxes` only. The sandbox itself has no cluster
network beyond internet + API/DNS ports, and exactly two credentials: the
`/root/.git-credentials` bot token that `sbx up` seeds (see above), and a
**read-only** kubectl access (SA `sandbox-ro` mounted with a kubeconfig that
goes through the `apiserver-proxy` pod — see [Sandboxes](sandboxes.md) for why
the node IP is not dialed directly). See [Sandboxes](sandboxes.md) for the
template and the warm pool.

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

The agent has its own Xfce desktop (TigerVNC `Xvnc` on a Unix socket under
`/opt/data/bot-desktop/`). Its `computer_use` tool and its browser act on it,
and the Hermes Desktop "Screen" pane shows it live and lets a human take over
for logins, 2FA or CAPTCHAs.

| Piece | Where it comes from |
|---|---|
| Xvnc, Xfce, Chromium | the upstream `-desktop` image (`nousresearch/hermes-agent:<version>-desktop`). The plain image lacks them, and the pane's "Install on host" button cannot add them: the gateway runs as `hermes` without `sudo` |
| `cua-driver` (computer_use) | installed by Hermes PM into `/opt/data/tools` by the `install-cua-driver` init container |
| headed browser | `browser.headed: true`, no `cdp_url`. While the screen is up the agent and the desktop's browser share one persistent profile, `/opt/data/bot-desktop/browser-profile` |
| screen on demand | `bot_desktop.auto_start: true`; it stops after 30 idle minutes |
| no prompt per click | every `cua:<action>:<mode>` key in `command_allowlist`. Hermes still hard-blocks dangerous typed shell patterns and destructive key combos |

Things that look broken and are not:

- `hermes computer-use doctor` reports **degraded**: AT-SPI is off. Hermes'
  launcher disables it on purpose (`NO_AT_BRIDGE=1`), so the agent works from
  screenshots and X11 input, and only `delivery_mode: foreground` lands.
- `capture` with `mode: vision` needs a model that reads images. The main
  model does, so `auxiliary.vision` stays on `auto`.

Renovate bumps the `-desktop` tag like any image: its docker versioning keeps
the suffix. Keep `seed-agent-src`, `install-cua-driver` and `hermes-carolyn` on
the same tag, since the webui runs the agent source `seed-agent-src` copies.

These keys live in the seeded `config.yaml`, which never overwrites the file
on the PVC: on an existing volume, apply them with `hermes config set`.

From a shell in the pod: `hermes computer-use screen status|start|stop`,
`hermes computer-use status`.

## Changing it

1. Edit the manifests in `mocha/apps/hermes-carolyn/manifests/`, never the pod.
   `selfHeal: true` reverts a manual `kubectl edit`.
2. Render in a sandbox — `kubectl kustomize` is the check that the change still
   parses and still produces every document.
3. If the change needs a new Vault key, write it first, then open the PR.
4. Open a PR. ArgoCD syncs it after merge; a seeding change may need the file
   deleted on the PVC to take effect.
