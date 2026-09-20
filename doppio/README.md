# `doppio` — Corium cluster (OVH bare metal)

Single-node Kubernetes cluster on an OVH dedicated server, kept for **storage and
backup**. One node: `ks-stor`.

Its address is deliberately not in this repo: substitute `<ks-stor>` in the
commands below.

Unlike `mocha/` and `turing/`, doppio is **not** Talos and **not** managed by Omni.
It runs [Corium](https://github.com/Corium-OS/Corium) — a bootc image around k0s —
and is driven with `cctl` instead of `omnictl`/`talosctl`. There is no
`template.yaml` and no `patches/` here; the equivalent is one document,
[`corium/ks-stor.yaml`](./corium/ks-stor.yaml).

## Who owns what

This is the part worth reading before changing anything, because doppio splits
ownership differently from the Talos clusters.

| Layer | mocha / turing | doppio |
|---|---|---|
| Day 0 (CNI + ArgoCD) | Talos `extraManifests` → raw `common/cilium` + `common/argocd` | k0s Helm charts, declared in `corium/ks-stor.yaml` |
| Day 2 on those | `helmfile apply` in CI | `cctl apply --file corium/ks-stor.yaml` |
| cert-manager | `common/cert-manager.yaml` via the `common` Application | same |
| Everything else | ApplicationSets over `system/*` and `apps/*` | same |

So **Cilium and ArgoCD are never ArgoCD Applications on doppio.** Making them
into ones would put the k0s Helm controller and ArgoCD on the same objects, and
they would take turns overwriting each other on every k0s restart. One owner,
declared in one file, versions pinned and bumped by Renovate.

`common/` is still consumed, exactly as on the other clusters — the `common`
Application is a non-recursive directory source, so what it actually reconciles
is `common/cert-manager.yaml`. The `common/cilium/` and `common/argocd/` trees
next to it are day-0 material for Talos and are simply not used here.

## Install

The machine was installed from OVH rescue mode; the procedure lives in
[Corium's rescue install guide](https://github.com/Corium-OS/Corium/blob/main/docs/install/rescue.md).
What matters for this repo:

1. The NoCloud seed written during the install carries the login user **and**
   three lines of Corium configuration:

   ```yaml
   corium:
     api:
       enabled: true
       awaitConfig: true
   ```

   `awaitConfig` is not optional. Without it the node bootstraps as an
   undescribed single-node cluster the moment it is claimed, its name becomes
   immutable, and the only way back is `cctl reset`.

2. Claim it and hand it its real configuration in one step — the document
   travels *with* the claim, so nothing races the bootstrap:

   ```bash
   cctl enroll <ks-stor>:7443 --code <code> --config doppio/corium/ks-stor.yaml
   ```

3. The node comes up `NotReady` until Cilium is running. That is `cni: custom`
   working as intended, not a failed boot: k0s installs the charts from the
   controller itself, so Cilium arrives without a scheduler.

4. Point ArgoCD at this repo, once:

   ```bash
   cctl kubeconfig <ks-stor> > /tmp/doppio.kubeconfig
   kubectl --kubeconfig /tmp/doppio.kubeconfig apply -f doppio/bootstrap/bootstrap.yml
   ```

## Day two

**Bumping Cilium or ArgoCD** — edit the version in `corium/ks-stor.yaml`, then:

```bash
cctl apply <ks-stor> --file doppio/corium/ks-stor.yaml
```

The node re-renders its k0s configuration and cycles the control plane to pick
the chart up. It reports `reconciled`, or `unchanged` if the document already
matches. Brief control-plane pause; the kubelet and its pods keep running.

**Anything else in that document** — role, node name, network, disks — is
refused with a `409` naming the field. Those are re-bootstrap territory:
`cctl reset`, then enroll again with the new document. That refusal is enforced
by the node, not by `cctl`, and an admin certificate does not get past it.

**Removing an add-on** is also refused, because k0s leaves a dropped chart
running and a node reporting the removal done would be lying. Delete the release
(`kubectl delete chart <name> -n kube-system`) and drop it from the document;
it stays out at the next bootstrap.

## Secrets

doppio runs **its own Vault** (bank-vaults / OpenBao) in `system/bank-vaults`,
rather than pointing external-secrets at mocha's. One more instance to unseal
and to back up, in exchange for a storage cluster that does not depend on the
production cluster being up.

Unsealing follows the same `mise` tasks as the others; the unseal keys for this
cluster are **not yet committed** — see the checklist below.

## Layout

```
doppio/
├── corium/ks-stor.yaml        # what the machine is (role, network, k0s charts)
├── bootstrap/bootstrap.yml    # applied once by hand: common + the two ApplicationSets
├── system/                    # reconciled by the doppio-system ApplicationSet
│   ├── bank-vaults/           # Vault, local to this cluster
│   ├── external-secret/       # external-secrets + ClusterSecretStore → local Vault
│   ├── openebs/               # local hostpath provisioner
│   └── openebs-storageclass/  # doppio-local, the default StorageClass
└── apps/                      # reconciled by the doppio-apps ApplicationSet (empty)
```

## Before this cluster is real

- [ ] **Disks.** `corium/ks-stor.yaml` has a commented `raid:` block and
      `openebs-storageclass` points at `/var/lib/doppio/local`. Run
      `lsblk -o NAME,SIZE,MODEL` on the node, fill the block in, and make the
      mount point match — a PVC landing on the root filesystem instead of the
      array is silent until the disk fills. Changing `raid:` needs a reset, so
      this is worth getting right before anything stores data.
- [ ] **Ingress.** `configs.cm.url` says `argocd.doppio.thoughtless.eu`, but
      there is no ingress controller in `system/` yet and no DNS record. Until
      there is, reach ArgoCD with `kubectl port-forward -n argocd svc/argocd-server 8080:80`.
- [ ] **Vault keys.** `mise vault:decrypt` expects `cluster-keys.json.age` next
      to the cluster. Initialise the Vault, then commit the age-encrypted keys
      here like `mocha/` and `turing/` do.
- [ ] **Backup wiring.** Nothing yet consumes doppio as a backup target. The
      obvious first move is an S3 endpoint (turing already runs `rustfs`) that
      mocha's VolSync/restic jobs can point at.
