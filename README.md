<p align="center">
    <img src="https://avatars.githubusercontent.com/u/82603435?v=4" width="140px" alt="Helm LOGO"/>
    <br>
    <a href="https://a-cup-of.coffee"><img src="https://readme-typing-svg.herokuapp.com?font=Fira+Code&pause=1000&center=true&vCenter=true&width=435&lines=Homelab+made+simple;Talos+go+brrrrr;GitOps+FTW;No+inspiration+for+what+I'm+going+to+write+here" alt="Typing SVG" /></a>
</p>

<div align="center">

  [![Blog](https://img.shields.io/badge/Blog-blue?style=for-the-badge&logo=buymeacoffee&logoColor=white)](https://a-cup-of.coffee/)
  [![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.36-blue?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kubernetes.io/)
  [![Talos](https://img.shields.io/badge/Talos-v1.13-blue?style=for-the-badge&logo=linux&logoColor=white)](https://talos.dev/)
  [![Corium](https://img.shields.io/badge/Corium-k0s-blue?style=for-the-badge&logo=linux&logoColor=white)](https://github.com/Corium-OS/Corium)

</div>

# HomeLab

<div align="center">

*Homelab setup based on Talos, Omni and Corium.*

</div>

## Overview

This repository contains the configuration files for my homelab. The homelab is a collection of servers and services that I run at home or in the cloud. The homelab is used for learning, testing, and hosting projects.

## Stack

The home cluster runs [Talos](https://www.talos.dev/) (don't hesitate to check [a little article I wrote about it](https://a-cup-of.coffee/blog/talos/)), managed by a self-hosted [Omni](https://www.siderolabs.com/platform/saas-for-kubernetes/) instance. The two OVH servers run [Corium](https://github.com/Corium-OS/Corium) (bootc + k0s) and are driven with `cctl`.

### Core Components

- [**Omni** (Self-hosted)](https://www.siderolabs.com/platform/saas-for-kubernetes/) : Manage the Talos nodes (**`turing`**).
- [**Corium**](https://github.com/Corium-OS/Corium) : bootc + k0s image for the OVH servers (**`mocha`**, **`doppio`**).
- [Cilium](https://cilium.io/) as CNI and LB (ARP mode)
- [ArgoCD](https://argoproj.github.io/argo-cd/) to manage the GitOps workflow
- [Traefik](https://doc.traefik.io/traefik/getting-started/install-traefik/#use-the-helm-chart) as Ingress controller (and for middleware management)
- [Cert Manager](https://cert-manager.io/) for TLS certificates
- [External DNS](https://kubernetes-sigs.github.io/external-dns/) to publish records from Ingresses
- Storage:
  - [Rook](https://rook.io/) (Ceph) on `turing`, plus [csi-driver-nfs](https://github.com/kubernetes-csi/csi-driver-nfs) for the NAS.
  - [OpenEBS](https://openebs.io/) on `mocha`: LVM (`openebs-lvmpv` by default, `openebs-lvmpv-thin`) and `openebs-hostpath`.
  - OpenEBS ZFS on `doppio` (`doppio-zfs`).
- [External Secrets](https://external-secrets.io/latest/) to fetch secrets from a remote store
- [OpenBao](https://openbao.org/) (via [bank-vaults](https://bank-vaults.dev/)) as secret store, one per cluster
- [Authentik](https://goauthentik.io/) for SSO / forward-auth, and [Dex](https://dexidp.io/) (**`mocha`**)
- [SigNoz](https://signoz.io/) + [OpenTelemetry Operator](https://github.com/open-telemetry/opentelemetry-operator) for metrics, logs and traces
- [CrowdSec](https://www.crowdsec.net/) to filter traffic hitting the Ingress (**`mocha`**)
- [Cloudflare Tunnels](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) to expose services to the internet (**`turing`**)
- restic CronJobs (database dumps, OpenBao snapshots) to S3 (**`mocha`**)
- [Spegel](https://spegel.dev/) to share images between nodes (**`turing`**)
- [Reloader](https://github.com/stakater/Reloader) to restart workloads when a ConfigMap/Secret changes
- Cluster API ([Virtink](https://github.com/smartxworks/virtink) + [Kamaji](https://kamaji.clastix.io/) providers) for guest clusters on `mocha`

### Clusters

- [**Mocha**](https://github.com/qjoly/GitOps/tree/main/mocha) : single bare-metal node hosted by OVH (128GB RAM, 8 CPU, 2x512GB NVMe), running Corium. Production cluster, also hosts SigNoz and the guest clusters. Its node document is [`mocha/corium/mocha.yaml`](./mocha/corium/mocha.yaml).
- [**Turing**](https://github.com/qjoly/GitOps/tree/main/turing) : cluster made of small devices (ARM and x86) at home. Local hosting, storage (Rook + NAS) and testing.
- [**Doppio**](https://github.com/qjoly/GitOps/tree/main/doppio) : single bare-metal node at OVH, kept for storage and backup. The odd one out — it runs [Corium](https://github.com/Corium-OS/Corium) (bootc + k0s) rather than Talos, so it is driven with `cctl` and has no Omni template. See [`doppio/README.md`](./doppio/README.md).
- [**Ristretto**](https://github.com/qjoly/GitOps/tree/main/ristretto) : single-node Talos VM on Proxmox, not managed by ArgoCD and reachable through ProxyAuthK8S. See [`ristretto/README.md`](./ristretto/README.md).

`cortado` and the standalone `kubevirt` cluster have been retired — the old configs live in the git history.

### Not Kubernetes

- [**Americano**](https://github.com/qjoly/GitOps/tree/main/americano) : a bare host running podman quadlets, reconciled by [Materia](https://github.com/stryan/materia) instead of ArgoCD. See [`americano/README.md`](./americano/README.md) for the branch trick that makes it work from a subdirectory.
- [`external/`](./external) : OTel collector and exporter units for machines outside the clusters (Proxmox hosts).

## Guest clusters on `mocha`

Instead of a second physical cluster for tests, `mocha` is meant to host [Cluster API](https://cluster-api.sigs.k8s.io/) guest clusters: a control plane hosted by Kamaji as pods, and workers as Virtink VMs. Their pod and service CIDRs live inside the guest, so they can overlap with the host cluster.

The only one defined is [`mocha/apps/kube-lab`](./mocha/apps/kube-lab). It does not sync yet: the CAPI core, the kubeadm bootstrap provider, CAAPH and the Kamaji operator are not installed. See [`mocha/clusters/README.md`](./mocha/clusters/README.md).

## Usage

**`turing`** is driven by Omni. Install [`omnictl`](https://omni.siderolabs.com/how-to-guides/install-and-configure-omnictl), merge the `omniconfig` downloaded from the Omni instance, then:

```bash
omnictl config merge ./omniconfig.yaml
omnictl cluster template sync -f turing/template.yaml
omnictl kubeconfig --cluster turing
```

**`mocha`** and **`doppio`** are driven by `cctl` with their node document, see [`doppio/README.md`](./doppio/README.md) for the full procedure:

```bash
cctl apply <node> --file mocha/corium/mocha.yaml
```

[`mocha/kubeconfig`](./mocha/kubeconfig) logs into `mocha` through Authentik (OIDC).

Recurring operations (Vault unseal and KV access) are `mise` tasks:

```bash
mise tasks          # list them
mise run vault:status
```

## CI/CD

| Workflow | What it does |
|----------|--------------|
| `omni-template-sync.yaml` | Syncs the Omni cluster template of `turing` on every push to `main` (see below) |
| `materia-americano.yaml` | Republishes `americano/` to the root of the `americano` branch for Materia |
| `tangled-mirror.yaml` | Mirrors the repo to tangled |
| `page.yaml` | Builds and publishes the mkdocs site ([docs](https://qjoly.github.io/GitOps/)) |
| `spindle-image.yaml`, `abcdesktop-image.yaml`, `atcr-hold-image.yaml` | Build the container images for a few self-hosted apps |

### Automatic cluster template sync

The workflow `.github/workflows/omni-template-sync.yaml` runs `omnictl cluster template sync` and `helmfile apply` on every push to `main` that modifies `turing/template.yaml`, `turing/patches/`, `turing/helmfile.yaml` or `turing/helm/`. On a pull request it posts the dry-run and the `helmfile diff` as a comment.

It authenticates against Omni using a **service account** (not a Kubernetes ServiceAccount — it is an Omni-native token-based credential).

### Create the Omni service account (one-time setup)

Run this once from a machine where `omnictl` is already configured:

```bash
omnictl serviceaccount create github-actions --role Operator --ttl 8760h
```

The command prints an `OMNI_ENDPOINT` and an `OMNI_SERVICE_ACCOUNT_KEY`. Store both as GitHub Actions secrets:

| Secret name                 | Value                             |
|-----------------------------|-----------------------------------|
| `OMNI_ENDPOINT`             | Endpoint printed by the command   |
| `OMNI_SERVICE_ACCOUNT_KEY`  | Key printed by the command        |

> The `OMNI_SERVICE_ACCOUNT_KEY` is shown only once — save it immediately.

Add them at: **Repository → Settings → Secrets and variables → Actions → New repository secret**

---

<details>
<summary>Example of kubeconfig file</summary>

```yaml
apiVersion: v1
kind: Config
clusters:
  - cluster:
      server: https://omni.home.une-tasse-de.cafe:8100/
    name: omni-turing
contexts:
  - context:
      cluster: omni-turing
      namespace: default
      user: omni-turing-quentinj@une-pause-cafe.fr
    name: omni-turing
current-context: omni-turing
users:
- name: omni-turing-quentinj@une-pause-cafe.fr
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      args:
        - oidc-login
        - get-token
        - --oidc-issuer-url=https://omni.home.une-tasse-de.cafe/oidc
        - --oidc-client-id=native
        - --oidc-extra-scope=cluster:turing
      command: kubectl
      env: null
      provideClusterInfo: false
```
</details>
