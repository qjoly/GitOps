# Spindle

[Spindle](https://docs.tangled.org/spindles) is the CI runner of [Tangled](https://tangled.org), a
social coding platform built on ATProto. Registering my own spindle means the pipelines of my
Tangled repositories run on mocha instead of someone else's hardware.

It runs in the `spindle` namespace on mocha, behind
[spindle.mocha.thoughtless.eu](https://spindle.mocha.thoughtless.eu).

## Building the image myself

There is no published container image for spindle, and that is not an oversight I could work around
— I checked before writing any manifest:

- The project *does* publish images, but on [atcr.io](https://atcr.io), an ATProto-native registry,
  and only for knots: `atcr.io/tangled.org/knot:latest`. `atcr.io/r/tangled.org/spindle` returns a
  404, and `atcr.io/u/tangled.org` lists exactly one image.
- `tngl/spindle:v1.10.0-alpha` is advertised in the README of the `spindle` branch of
  `psychedeli.ca/knot-docker`, but it was never pushed — the whole `tngl` Docker Hub namespace only
  contains `knot`.
- `.tangled/workflows/build.yml` upstream only runs `go build -o spindle.out ./cmd/spindle`. No
  registry login, no push.
- `flake.nix` has no `dockerTools` / `buildLayeredImage` call anywhere.

One trap worth naming: `nix build .#spindle-alpine-image` looks like it produces a spindle
container. It does not — those `*-image` attributes build **microVM guest rootfs** bundles (a
minirootfs plus `vmlinuz-virt`, tarred up) that spindle boots *to run CI jobs inside*. Wrong
direction entirely.

So `.github/workflows/spindle-image.yaml` clones the upstream monorepo at a tag and builds
`localinfra/spindle.Dockerfile` into `ghcr.io/qjoly/spindle`. It is `workflow_dispatch` only, with
the tag as an input:

```bash
gh workflow run spindle-image.yaml -f ref=v1.16.1-alpha
```

Then bump the tag in `mocha/apps/spindle/manifests/deployment.yaml`. Renovate does not track this,
since upstream does not live on GitHub.

That Dockerfile is marked *"Development only. Not for production use."* I use it anyway: it is a
plain multi-stage Go build, and the alternative is maintaining my own. The `git clone` works over
plain HTTPS — it redirects to `knot1.tangled.sh`.

## Which engine, and why the dind sidecar

Spindle ships two engines, and both still work — the microVM one is *"an upgrade from the existing
Nixery engine while staying fully compatible with it, so if you already have a working Nixery
workflow, just change `nixery` to `microvm` and it will work"*.

I picked **nixery**, because it needs nothing but a Docker API: images are pulled on demand from
`nixery.tangled.sh`. The **microvm** engine would require me to build NixOS/Alpine guest images with
Nix and ship them into a PVC, since nobody distributes them.

Upstream says spindle must run natively on the host because *"Docker-in-Docker hasn't been
implemented yet"*. That turns out not to apply to a sidecar, and the code says why:

- `spindle/engines/nixery/engine.go` connects with `client.NewClientWithOpts(client.FromEnv, ...)`,
  so it honours `DOCKER_HOST`.
- Its `ContainerCreate` call makes **no host bind mounts**: `/tmp` is a tmpfs and the workspace
  lives inside the workflow container. The only bind it can ever request comes from
  `SPINDLE_SERVER_DOCKER_SOCKET`, which I leave unset.

No shared filesystem is needed, so a `docker:dind` sidecar reachable over TCP is enough. Both
containers share the pod network namespace, so `127.0.0.1:2375` works across them.

mocha does have `/dev/kvm` and the `vmx` CPU flag, so switching to the microVM engine later is
possible. The node even advertises `devices.kubevirt.io/kvm` as a schedulable resource, which is a
cleaner way to get the device than a `hostPath`.

## Making dind listen on loopback only

The sidecar first crashed with exit code 1. Reading
[`dockerd-entrypoint.sh`](https://github.com/docker-library/docker/blob/master/29/dind/dockerd-entrypoint.sh)
rather than guessing explained it. The guard is:

```sh
# no arguments passed
# or first arg is `-f` or `--some-option`
if [ "$#" -eq 0 ] || [ "${1#-}" != "$1" ]; then
```

My arguments started with `-`, so the script **prepended** its own hosts and appended mine:

```
dockerd --host=unix:///var/run/docker.sock --host=tcp://0.0.0.0:2375 --host=tcp://127.0.0.1:2375 ...
```

Two binds on port 2375, so the daemon refused to start.

The crash was hiding the real problem. Had I simply dropped my arguments, dind would have started
fine — exposing an **unauthenticated root-equivalent Docker API on the pod IP**, reachable from
anywhere in the cluster. Workflow containers are created by that very daemon, sit on the same
network, and get `host.docker.internal:host-gateway`, so untrusted pull-request code could have
reached the socket and escaped to root on the node.

Passing `dockerd` as the first argument skips the defaults block while still hitting
`if [ "$1" = 'dockerd' ]` further down, which keeps the actual dind setup. The result is a strict
loopback bind:

```
$ kubectl -n spindle logs deploy/spindle -c dind | grep "API listen"
API listen on /var/run/docker.sock
API listen on 127.0.0.1:2375
```

`--tls=false` states the intent explicitly and skips the deliberate startup delay Docker adds when
it thinks you forgot about TLS.

## Memory limits are not decorative

Workflow containers are children of that `dockerd`, so their memory counts against the **dind**
container's cgroup, not spindle's. The limits are sized together:

| Setting | Value |
|---|---|
| `SPINDLE_NIXERY_PIPELINES_MAX_CONCURRENT_WORKFLOWS` | 2 |
| `SPINDLE_NIXERY_PIPELINES_MAX_JOB_MEMORY_MB` | 4096 |
| dind `limits.memory` | 10Gi |

Raise either of the first two without raising the limit and the daemon gets OOM-killed mid-job. The
upstream defaults (8 concurrent × 6144 MB) would need 48Gi.

The Docker data directory is an `emptyDir` with a 30Gi limit — a throwaway image cache. Worth moving
to a PVC if re-pulling from nixery on every restart becomes annoying.

## What spindle serves over HTTP

Four routes, from `spindle/server.go`:

| Route | What it is |
|---|---|
| `/` | an embedded motd, answered without touching the database, jetstream or docker |
| `/events` | event stream |
| `/logs/{knot}/{rkey}/{name}` | workflow logs, read back by the appview |
| `/xrpc/*` | the XRPC API |

`/` is the useful probe target, precisely because it depends on nothing else. Worth spelling out
because `grep` for route registrations is easy to get wrong here: they use `mux.HandleFunc(`, so a
pattern like `mux\.(Get|Handle|Mount)\(` matches only the `/xrpc` mount and makes it look like the
sole route.

## PodSecurity

The dind sidecar is privileged, and mocha enforces the `baseline` PodSecurity profile cluster-wide
(a Talos default), which forbids exactly that. Symptom: the Argo Application reports `Synced` while
the ReplicaSet sits at `DESIRED 1 / CURRENT 0`. The reason only shows up in its events:

```
Error creating: pods "spindle-…" is forbidden: violates PodSecurity "baseline:latest":
privileged (container "dind" must not set securityContext.privileged=true)
```

Beware of testing this with a server-side dry run against `default` — that namespace already carries
`enforce: privileged`, so it passes and tells you nothing.

The `managedNamespaceMetadata` pattern used by `crowdsec` and `wazuh` did **not** work here. The
field was applied to the Application, but the namespace had already been created by an earlier sync
via `CreateNamespace=true`, and Argo never retrofits the labels onto it — not even after
`argocd.argoproj.io/refresh=hard`. It does not appear among the Application's managed resources at
all.

So the namespace is declared explicitly in `manifests/namespace.yaml`, the way `bank-vaults` does
it, and gets applied like any other resource. `managedNamespaceMetadata` was removed to keep a
single source of truth.

## Log directory

`SPINDLE_SERVER_LOG_DIR` stays at its default `/var/log/spindle`, and that is load-bearing.
`spindle/models/logger.go` opens log files with `os.OpenFile` and **no** `MkdirAll`, so the
directory has to exist beforehand. The only thing that creates it is the image entrypoint, with that
path hardcoded. Pointing the variable elsewhere silently breaks log writing.

Both the SQLite databases and the logs live on one PVC, mounted twice with different `subPath`s.

## Registering the spindle

Nothing needs to be published for `did:web` to work. `serviceauth.DidWeb()` derives
`did:web:spindle.mocha.thoughtless.eu` from the hostname, which suggests a DID document is required
— but the codebase never serves `/.well-known/did.json` anywhere. That
DID is only ever used as the `aud` claim when validating inbound service-auth JWTs.

Registration happens in the Tangled UI (settings → spindles), which writes an `sh.tangled.spindle`
record to my PDS. Spindle is already subscribed to it over jetstream, so no redeploy is needed.

Health check, unauthenticated:

```bash
$ curl https://spindle.mocha.thoughtless.eu/xrpc/sh.tangled.owner
{"owner":"did:plc:hqnyog7skad6m4aejb2yujxy"}
```

## One harmless error in the logs

```
ERRO spindle: failed to save cursor on shutdown system=tap component=firehose error="context canceled"
```

This is upstream cosmetics, not a misconfiguration. `spindle/tap_drain.go` shuts the embedded tap
down on purpose once there is nothing left to backfill (`stop()` then `embedTap.Shutdown()`), and
the cursor save races that context cancellation. It fires because no repositories are attached yet,
and goes quiet afterwards.
