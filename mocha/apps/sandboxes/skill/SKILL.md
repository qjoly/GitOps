---
name: sbx
description: Use when a build, test suite, script or web research should run outside this machine - untrusted code, heavy builds, toolchains not installed locally, or several tasks to run in parallel. Drives disposable gVisor sandboxes on the mocha cluster with the `sbx` CLI; code is pushed from the local checkout and changes come back as a git patch.
---

# Sandboxes on mocha (`sbx`)

The local checkout stays the source of truth. A sandbox gets a copy, works on it, and hands back a patch. git commits, pushes and `gh` (PR, review, issues) only ever run locally, after the patch is applied.

Never pass a token, kubeconfig or any secret into a sandbox: it has none on purpose.

## Flow

```bash
n=$(sbx up)                       # prints the sandbox name
sbx push "$n" .                   # replaces /work with the checkout (gitignored files stay local)
sbx exec "$n" -- bash -c 'mise install && make test'
sbx diff "$n" > /tmp/$n.patch     # everything changed in /work since the push
git apply /tmp/$n.patch
sbx down "$n"
```

- Always `sbx down` when done, even after a failure. Forgotten sandboxes die after 4 h (`SBX_TTL=<seconds> sbx up` to change it).
- `exec` runs argv as-is in `/work`: wrap pipes, `&&` and globs in `bash -c '…'`. Stdin is forwarded, so `sbx exec "$n" -- bash -c 'cat > x' < x` works.
- Run long builds in the background instead of blocking on them.
- Read the patch before applying it: it is the only thing that crosses back.

## Parallel work

One sandbox per task, each `up` is independent. To keep patches from colliding, give each task its own local `git worktree` and branch, push from it, and apply its patch there.

## Inside the sandbox

- Debian trixie with build-essential, git, curl, python3, running as root: `apt-get install` works.
- `mise install` reads the repo's `mise.toml`; `mise use -g node@22` for anything else.
- Internet is open, the cluster network is not reachable. Research is just `curl` from `exec`.
- Up to 4 CPU, 8 GiB RAM, 30 GiB disk. Write only under `/work`, `/root` or `/tmp`: the rest of the filesystem lives in RAM.

## Build artifacts

They are usually gitignored, so `diff` leaves them out. Stream them back with tar:

```bash
sbx exec "$n" -- tar czf - -C /work dist | tar xzf -
```

## When something fails

- `sbx up` hangs or errors: `sbx ls`, then check the mocha OIDC login (`kubectl --kubeconfig ~/code/perso/GitOps/mocha/kubeconfig --context mocha get ns` may need a browser).
- `git apply` refuses the patch: the local checkout moved since the push. Try `git apply --3way`, or push again and redo the work.
