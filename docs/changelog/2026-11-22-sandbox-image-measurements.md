# Sandbox image: what it costs and what it buys, measured

**Started:** 2026-11-22
**Scope:** measurements only. Step 6 of `SANDBOX-IMAGE-PLAN.md`; the image
itself landed in #657 / #658 / #659. Nothing here changes a manifest — see
"What was found and not fixed" at the end.

## Why

gVisor keeps the container root filesystem in memory, so every binary added to
the image is paid by every warm-pool pod, permanently. The custom image
(`mocha/apps/sandboxes/image/`) exists to remove two startup costs — the
`curl https://mise.run | sh` download and the per-task `gh`/`jq`/`kubectl`
download — but it has to earn its RAM back.

## The figures

| | avant | après | delta |
|---|---|---|---|
| Image, compressed layers | 380.1 MB (`buildpack-deps:trixie`, `docker.io/…@sha256:0bcdd861`) | 477.9 MB (`ghcr.io/qjoly/sandbox-dev@sha256:e3b74538…`) | **+97.8 MB (+25.7 %)** |
| Image, upper bound on what gVisor holds in RAM (sum of uncompressed layer sizes, measured by decompressing every blob) | 997.1 MiB | 1,281.6 MiB | **+284.5 MiB (+28.5 %)** |
| Warm-pool pod, `PodScheduled` → `ContainersReady` | 4.8 s, 5.5 s, 6.2 s, 7.0 s (four pods on `buildpack-deps:trixie`) | 1.0 s (`dev-fhw4h`, on the image) | **−3.8 s to −6.0 s** |
| `mise` bootstrap inside the pod | 3.1 s (`curl -fsSL https://mise.run \| sh`, measured in a live sandbox) | 0 s (baked at `/usr/local/bin/mise`) | **−3.1 s** |

Both sides on node `mocha`, same `SandboxTemplate` `dev`. The "avant" numbers
are the four pods created 2026-11-22 between 16:36 and 17:48 (still on
`buildpack-deps:trixie`); the "après" number is `dev-fhw4h`, the warm-pool
replacement pod created at 19:57:44Z after the template moved to the image.
The pod-start saving is bounded by the bootstrap it removes: minus ~3.1 s of
`mise.run` download leaves ~1.7–3.9 s per cold pod, which is what a regression
in image size would have to claw back.

## Where the +284.5 MiB goes

Per layer, from the OCI manifest (tag `2026.11.12` → index
`sha256:e3b74538…` → amd64 manifest `sha256:d8313330…`). The first four layers
are byte-identical to the base image; everything below is the image's own
contribution:

| Layer | Step | On disk (uncompressed) |
|---|---|---|
| 4 | `apt-get install jq ca-certificates` | 2.4 MiB |
| 5 | `kubectl` v1.37.2 (dl.k8s.io) | 39.3 MiB |
| 6 | `gh` 2.105.0 (release tarball) | 59.0 MiB |
| 7 | `mise.toml` pin copied to `/usr/local/share/sandbox-image/` | 0.0 MiB |
| 8 | `mise` 2026.11.12 (release tarball) | 183.7 MiB |
| | total | 284.5 MiB |

This overturns the assumption the step-6 DoD was written on:

- **`mise` is the most expensive thing in the image**: 183.7 MiB, three times
  `gh` and nearly five times `kubectl`. The pinned release tarball unpacks to
  that for one binary, against the ~40 MB the `mise.run` installer fetches at
  boot. It is still the right trade (183 MiB held once per warm pod against
  ~40 MB downloaded on every boot), but it is not a small addition.
- **The fallback target is wrong.** The DoD says to drop `kubectl` first
  "because it is the biggest addition after `gh`". It is the opposite: `kubectl`
  is the *smallest* of the three (39.3 MiB) and `gh` is next at 59.0 MiB.
  Dropping `kubectl` would recover 14 % of the increase. If RAM ever becomes the
  constraint the order is `mise` → `gh` → `kubectl`, and the first question is
  whether `mise` can be a smaller build, not which binary to cut.
- In relative terms the image is unremarkable: +28.5 % on disk, 1.25 GiB total,
  on top of a 997 MiB base.

## Is it over the pod budget?

Not close. The container requests `1Gi` and is limited to `8Gi`; the entire
image is 1.25 GiB uncompressed, and gVisor faults pages in lazily, so a warm
pod's resident set is what its processes touch, not the whole rootfs. In the
same window the sandboxes namespace requested 3.0 of the node's 12 cores
against 12.63 cores of pod requests cluster-wide, which is why the warm-pool
replacement pod sat `Pending` with `0/1 nodes are available: 1 Insufficient
cpu` once a fifth claim was live. The node was CPU-bound, not memory-bound: the
image did not contribute to the scheduling failure.

## Why `kubectl top pod` cannot answer this, and what to read instead

`kubectl top pod -n sandboxes` reports **2 MiB for every running sandbox**, and
`369Mi` for exactly one — including a pod running a full `make` at 828m CPU.
cAdvisor under `runsc` does not account the sandbox kernel's page cache, so that
number is anonymous memory only. The honest figures come from the image
(uncompressed layer sizes = the upper bound on what gVisor must be able to hold)
and from the pod timeline (`PodScheduled` → `ContainersReady`), both
reproducible with the commands below.

## How to reproduce

```bash
# Image size, compressed and uncompressed, with a per-layer split.
T=$(curl -s "https://ghcr.io/token?scope=repository:qjoly/sandbox-dev:pull" | jq -r .token)
curl -s -H "Authorization: Bearer $T" -H 'Accept: application/vnd.oci.image.index.v1+json' \
  https://ghcr.io/v2/qjoly/sandbox-dev/manifests/2026.11.12 | jq -r '.manifests[].digest'
# /manifests/<amd64 digest> gives layers[].size; /blobs/<config digest> gives
# rootfs.diff_ids and history[].created_by, which attributes each layer.
# Uncompressed sizes: GET /blobs/<layer digest> piped through `gzip -dc | wc -c`
# (the layer is a gzipped tar, so this is what the registry never reports).
# docker.io/library/buildpack-deps:trixie goes through auth.docker.io with the
# same three calls; take the amd64 entry of its index.

# Pod start: creation time and the ContainersReady transition.
kubectl --kubeconfig /opt/sbx/kubeconfig --context mocha -n sandboxes \
  get pod <pod> -o jsonpath='{.status.startTime}{"\n"}{range .status.conditions[*]}{.type}={.lastTransitionTime} {end}'

# Warm-pool pod identity and image digest.
kubectl --kubeconfig /opt/sbx/kubeconfig --context mocha -n sandboxes \
  get pods -l agents.x-k8s.io/warm-pool-sandbox \
  -o custom-columns='N:.metadata.name,IMG:.spec.containers[0].image,ID:.status.containerStatuses[0].imageID'
```

## What was found and not fixed: the live pool does not run the published build

Tags `2026.11.12` and `latest` both resolve to
`sha256:e3b74538a490f34c6490dc1a7f0aada1e051e75b0c56b885d0325d8375c6b986`
(built 19:51:46Z from `1e6125d1`, workflow run #2). The warm-pool pod and every
pod created since 19:41 are on
`sha256:ff995f55f0e363374fc3891c351bd4853053f719a1e727cf968d0052fe4a60e1`, the
*pre-fix* build: `/etc/mise/mise.toml` is still present, `mise config ls` lists
it as a runtime config beside `/work/mise.toml`, and `mise install` in a sandbox
still fails with `mise ERROR mise not found in mise tool registry`. The size
figures above are for the corrected `e3b74538`; the start-time figures are for
a pod on the pre-fix build. The two differ by nothing that moves either number —
the fix relocates a 270-byte file and edits an env var.

`kubectl -n sandboxes get pod -o jsonpath='{.spec.containers[0].image}'` returns
the tag, so it cannot tell the two builds apart; only
`.status.containerStatuses[0].imageID` can. A mutable tag that now means two
different bytes depending on when a pod started is the argument for pinning
`dev.yaml` by digest. Closing the gap needs free CPU on the node and write
access to the sandbox namespace: `kubectl delete pod <warm-pool pod>` (the
controller recreates it from the tag, i.e. the fixed image), or bump the
template to the new digest.
