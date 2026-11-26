# Sandboxes

Disposable sandboxes on mocha where a local agent (or I) can build, run tests and browse the web
without touching my laptop. The code stays on my disk: a sandbox gets a copy, and what it changes
comes back as a git patch. git pushes and `gh` only run locally.

> **Warning:** the agent-sandbox controller and the `gvisor` RuntimeClass are installed on mocha by
> hand, not by this repository. `mocha/apps/sandboxes` only holds the template and the warm pool.

## How it fits together

```mermaid
sequenceDiagram
    participant L as Laptop (sbx)
    participant K as mocha API server
    participant S as Sandbox pod (gVisor)
    L->>K: sbx up: SandboxClaim on the dev warm pool
    K-->>L: claim Ready, sandbox name
    L->>S: sbx push: tar of the checkout over kubectl exec
    L->>S: sbx exec: commands in /work
    S-->>L: sbx diff: git patch since the push
    L->>L: git apply, commit, gh pr create
    L->>K: sbx down: claim deleted
```

- **Isolation**: every pod runs under gVisor. The template's custom network policy
  (`spec.networkPolicy` in `manifests/dev.yaml`) allows internet egress plus, on ports 443/6443
  (API) and 53 (DNS), traffic to cluster pods — see below for why it is pod-based, not CIDR-based.
- **Storage**: no live mount. The checkout is copied in and changes come back as a patch, so builds
  run on the sandbox disk at full speed and nothing lives only in the cluster.
- **Credentials**: the sandbox gets exactly two, both mounted/seeded file-only, never as env vars
  (the template's `envVarsInjectionPolicy: Disallowed` blocks claim-time env injection):
  - the `unetassedecafe` bot token at `/root/.git-credentials` (mode 0600, seeded by `sbx up` /
    the kube-sandbox plugin), so `git`/`gh` in the VM act as the bot;
  - a **read-only** Kubernetes access: SA `sandbox-ro` (ClusterRole `sandbox-readonly` =
    get/list/watch + pods/log only, bound cluster-wide), mounted as
    `/var/run/secrets/kubernetes.io/serviceaccount/` plus `KUBECONFIG=/etc/sandbox-ro/kubeconfig`.
    The kubeconfig points at the `apiserver-proxy` Service (a socat pod forwarding to the node
    API), because Cilium classifies the node IP as `reserved:host` and denies egress to it —
    ipBlock rules never match pod/host identities, only `world`, so the netpol allows the
    needed ports via `namespaceSelector: {}` (all cluster pods) instead of CIDRs.

  `mise install` still does not call the GitHub API: the `github` backend resolves releases
  through `mise-versions.jdx.dev`, which spends a pooled token upstream. Check it with
  `mise token github`, which reports `(none)` on a healthy sandbox. Only a `mise-versions` outage
  falls back to anonymous `api.github.com` calls.

See [Hermes](hermes.md) for the pod that drives these sandboxes and publishes the result.

## Install

```bash
ln -s ~/code/perso/GitOps/mocha/apps/sandboxes/sbx ~/.local/bin/sbx
ln -s ~/code/perso/GitOps/mocha/apps/sandboxes/skill ~/.claude/skills/sbx
```

`sbx` talks to mocha through `mocha/kubeconfig` and the `mocha` context, whatever the current
context is. `SBX_KUBECONFIG`, `SBX_CONTEXT` and `SBX_NAMESPACE` override them.

The skill tells Claude Code when to reach for a sandbox and how to use it.

## Usage

```bash
n=$(sbx up)                        # claim a sandbox, prints its name
sbx push "$n" .                    # replace /work with the checkout
sbx exec "$n" -- bash -c 'mise install && make test'
sbx diff "$n" | git apply          # bring the changes back
sbx down "$n"
```

| Command | Effect |
|---|---|
| `up [name]` | Claims a sandbox and waits until it is ready. It is deleted after 4 h, or `SBX_TTL` seconds. |
| `push <name> [dir]` | Sends tracked and untracked files plus `.git`, minus gitignored ones. Local uncommitted edits are part of the baseline. |
| `exec <name> -- cmd…` | Runs argv in `/work`, stdin forwarded. Use `bash -c` for pipes and globs. |
| `diff <name>` | Prints a binary-safe patch of everything changed since the push. |
| `down <name>` / `ls` | Deletes / lists sandboxes. |

Build artifacts are gitignored, so they are not in the patch. Stream them back with tar:

```bash
sbx exec "$n" -- tar czf - -C /work dist | tar xzf -
```

For parallel tasks, give each sandbox its own `git worktree` so patches do not collide.

## Inside a sandbox

- `buildpack-deps:trixie` as root: compilers, git, curl, python3, and `apt-get` works.
- mise is installed when the pod starts, and the sandbox is only handed out once that is done.
  `mise install` picks up the repo's `mise.toml`; `mise use -g node@22` installs anything else.
- Up to 4 CPU and 8 GiB of RAM, 30 GiB of disk.
- gVisor keeps the root filesystem in RAM, so `/work`, `/root` and `/tmp` are on disk. Write anywhere
  else and it counts against the memory limit.

One sandbox always waits in the warm pool and is handed out within seconds. The others start cold in
about 6 seconds, mise download included.

## Troubleshooting

- `sbx up` hangs: run `sbx ls`, then
  `kubectl --kubeconfig mocha/kubeconfig --context mocha get ns`, which may need a browser for the
  OIDC login.
- `git apply` refuses the patch: the checkout moved since the push. Try `git apply --3way`.
- `mise: command not found`: the download from mise.run failed when the pod started. Install it
  with `sbx exec "$n" -- bash -c 'curl -fsSL https://mise.run | sh'`.
