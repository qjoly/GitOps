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

## Storage

The array is not what `corium/ks-stor.yaml` would build. It predates this
cluster: four 4 TB disks in a raidz1 `datapool`, created by the TrueNAS install
that used to run on this machine, imported as-is by Corium. That is why the
`raid:` block in the node document is still commented out — filling it in would
mean a reset, and a reset would mean wiping 384 GB of data that is only here.

```
datapool                  raidz1, 4 × 4 TB, lz4, encrypted   9.9 TiB free
├── Administratif         read-only, replicated from TrueNAS
├── InfoTech              read-only, replicated from TrueNAS
├── Utilisateurs          read-only, replicated from TrueNAS
└── k8s                   parent of every PVC on doppio
```

Every dataset is encrypted, and the keys are files under `/etc/zfs` loaded at
boot by `corium-zfs-loadkey.service`. **The key of the pool's own root dataset,
`/etc/zfs/datapool.key`, is gone** — it went with the TrueNAS install. The
practical consequences:

- the 161 GB written directly into `datapool` cannot be read, and
  `/var/mnt/data` is a plain directory rather than a mount. Nor can that space
  be reclaimed: a pool's root dataset cannot be destroyed, only the pool can,
  so those 161 GB are charged to the array until the day it is rebuilt;
- `ix-applications`, the other dataset that inherited the pool key, was
  destroyed — it held 2.4 GB of TrueNAS app state that nothing can read;
- a dataset cannot be created under an encryption root whose key is
  unavailable, so `datapool/k8s` carries **its own** key
  (`/etc/zfs/stockage.key`, the same one the three replicated datasets use).

`datapool/k8s` was created once, by hand, and is not reconciled by anything:

```bash
sudo zfs create -o mountpoint=none \
  -o encryption=aes-256-gcm -o keyformat=hex \
  -o keylocation=file:///etc/zfs/stockage.key \
  datapool/k8s
```

From there `openebs-storageclass` is ordinary GitOps: `doppio-zfs` is the
default class, every PVC becomes a `datapool/k8s/pvc-*` dataset with
`mountpoint=legacy`, thin-provisioned, inheriting the pool's compression and the
dataset's encryption. `doppio-local` (hostpath, on the root filesystem) is kept
only for the volumes bound before the array was wired up.

> Back up `/etc/zfs/stockage.key`. It is the only copy, and losing it loses the
> replicated datasets and every PVC in one go — exactly how `datapool.key` was
> lost.

## Ingress

traefik takes the machine's single public address through `externalIPs` on its
Service, not through a LoadBalancer (no controller) and not through a hostPort.

The hostPort is worth a sentence, because it looks like the obvious answer and
it fails in a way that takes a while to see. Cilium only implements hostPort
itself when it replaces kube-proxy, which it does not here; the fallback is the
`portmap` CNI plugin, chained after `cilium-cni`. That publishes 80 and 443 to
the internet correctly — and not to pods, because Cilium's datapath never shows
pod egress to portmap's DNAT rules. The one pod that has to reach the ingress by
its public name is cert-manager, doing the HTTP-01 self check, so no certificate
is ever issued and nothing says why. `externalIPs` is served by the same path as
a ClusterIP and works from both sides.

Certificates come from `letsencrypt`, an HTTP-01 ClusterIssuer, rather than the
DNS-01 Cloudflare issuer mocha and turing share: doppio's Vault is its own, and
this cluster already answers on :80. The `web` entrypoint redirects everything
to TLS except the ACME challenge, which is what `allowACMEByPass` is for.

## Layout

```
doppio/
├── corium/
│   ├── ks-stor.yaml           # what the machine is (role, network, k0s charts)
│   └── corium-zfs-loadkey.service  # copy of a unit applied by hand on the node
├── bootstrap/bootstrap.yml    # applied once by hand: common + the two ApplicationSets
├── system/                    # reconciled by the doppio-system ApplicationSet
│   ├── argocd-config/         # the OIDC client secret, nothing else
│   ├── bank-vaults/           # Vault, local to this cluster
│   ├── external-secret/       # external-secrets + ClusterSecretStore → local Vault
│   ├── misc/                  # the letsencrypt ClusterIssuer
│   ├── openebs/               # zfs-localpv (+ hostpath, for what already uses it)
│   ├── openebs-storageclass/  # doppio-zfs, the default StorageClass
│   ├── prometheus-operator-crds/  # only so common/'s ServiceMonitors render
│   └── traefik/               # the ingress controller
└── apps/                      # reconciled by the doppio-apps ApplicationSet
    ├── deluge/                # https://deluge.doppio.thoughtless.eu
    ├── flexget/               # https://flexget.doppio.thoughtless.eu
    └── kavita/                # https://kavita.doppio.thoughtless.eu
```

## The media namespace

kavita, deluge and flexget are one stack in one namespace, `media`, because
they share a volume and a PVC does not cross namespaces. `kavita-library` is
mounted twice — Kavita reads it, deluge writes finished downloads into it —
which is what `shared: "yes"` on the `doppio-zfs` class is for. The node is
single, so that is the whole of what ReadWriteMany would have bought.

flexget polls an RSS feed, filters it and hands matches to deluge over the
daemon protocol. Two things about that are worth knowing before editing it:

- **The feed is filtered to nothing by default.** The `accept` list in the task
  holds `(?!)`, a regexp that matches no string. Replace it with one entry per
  title to follow — an unfiltered nyaa feed is thousands of entries a day.
- **The daemon password is generated on first start**, by deluge's init
  container, and kept on the little `deluge-rpc` volume that flexget also
  mounts. Nothing writes it to git and nothing asks anyone to type it in. The
  chart has a generator for this, but it is built on a Helm `lookup`, and
  ArgoCD renders with `helm template` — it produces an empty Secret.

The flexget web UI is the exception: its password has to be readable by a
human, so it lives in this cluster's Vault at `kv/flexget`, pulled in by an
ExternalSecret. The username is `flexget`.

## Logging into ArgoCD

`argocd.doppio.thoughtless.eu`, behind traefik, with a Let's Encrypt
certificate. Accounts come from **mocha's authentik** — the provider is
declared in `mocha/system/authentik/authentik.yaml` under the slug
`argocd-doppio`, and membership of the `authentik Admins` group is what grants
`role:admin`. Without it a successful login lands on nothing, since
`policy.default` is empty.

Two things do not follow from that automatically:

- **The ingress and the dex connector live in `corium/ks-stor.yaml`**, not in
  an Application, for the reason at the top of this file: ArgoCD here is a k0s
  chart, and a second owner of `argocd-cm` would fight the Helm controller on
  every restart. Changing them means `cctl apply`, not a git sync.
- **The client secret is copied by hand.** mocha's provisioner mints it into
  the `oidc-argocd-doppio` Secret on mocha; this cluster reads it from *its
  own* Vault at `kv/argocd`, because doppio deliberately does not depend on
  mocha's. Rotating the provider means copying the pair across again.

This does put the login path on mocha: if mocha is down, OIDC here is down with
it. The local `admin` account stays enabled as the way back in.

## Before this cluster is real

- [ ] **Vault off the root filesystem.** `vault-raft-vault-0` was bound before
      the array was usable and is still on `doppio-local`, i.e. on the 10 GiB
      root image. Moving it means a Vault snapshot, a new PVC on `doppio-zfs`
      and a restore; it is the last thing left on hostpath.
- [ ] **Vault keys.** `mise vault:decrypt` expects `cluster-keys.json.age` next
      to the cluster. Initialise the Vault, then commit the age-encrypted keys
      here like `mocha/` and `turing/` do.
- [ ] **Backup wiring.** Nothing yet consumes doppio as a backup target. The
      obvious first move is an S3 endpoint (turing already runs `rustfs`) that
      mocha's VolSync/restic jobs can point at.
