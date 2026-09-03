<p align="center">
    <img src="https://avatars.githubusercontent.com/u/82603435?v=4" width="140px" alt="Helm LOGO"/>
    <br>
    <a href="https://a-cup-of.coffee"><img src="https://readme-typing-svg.herokuapp.com?font=Fira+Code&pause=1000&center=true&vCenter=true&width=435&lines=Homelab+made+simple;Talos+go+brrrrr;GitOps+FTW;No+inspiration+for+what+I'm+going+to+write+here" alt="Typing SVG" /></a>
</p>

<div align="center">

  [![Blog](https://img.shields.io/badge/Blog-blue?style=for-the-badge&logo=buymeacoffee&logoColor=white)](https://a-cup-of.coffee/)
  [![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.35.6-blue?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kubernetes.io/)
  [![Linux](https://img.shields.io/badge/Talos-v1.13.5-blue?style=for-the-badge&logo=linux&logoColor=white)](https://talos.dev/)

</div>

# HomeLab

<div align="center">

*Homelab setup based on Omni and Talos.*

</div>

## Overview

This repository contains the configuration files for my homelab. The homelab is a collection of servers and services that I run at home or in the cloud. The homelab is used for learning, testing, and hosting projects.

## Stack

To avoid headaches and to keep things simple, I use [Talos](https://www.talos.dev/) to manage the Kubernetes cluster (don't hesitate to check [a little article I wrote about it](https://a-cup-of.coffee/blog/talos/)). To be more specific, I have a self-hosted [Omni](https://www.siderolabs.com/platform/saas-for-kubernetes/) instance to manage all clusters with a single endpoint and secure them with SSO.

### Core Components

- [**Omni** (Self-hosted)](https://www.siderolabs.com/platform/saas-for-kubernetes/) : Manage all nodes between clusters and regions.
- [Cilium](https://cilium.io/) as CNI and LB (ARP mode)
- [ArgoCD](https://argoproj.github.io/argo-cd/) to manage the GitOps workflow
- [Traefik](https://doc.traefik.io/traefik/getting-started/install-traefik/#use-the-helm-chart) as Ingress controller (and for middleware management)
- [Cert Manager](https://cert-manager.io/) for TLS certificates
- [External DNS](https://kubernetes-sigs.github.io/external-dns/) to publish records from Ingresses
- Storage:
  - [Rook](https://rook.io/) (Ceph) on `turing`, plus [csi-driver-nfs](https://github.com/kubernetes-csi/csi-driver-nfs) for the NAS.
  - [OpenEBS](https://openebs.io/) + LVM on `mocha` (`openebs-lvmpv` is the only StorageClass there).
- [External Secrets](https://external-secrets.io/latest/) to fetch secrets from a remote store
- [Vault](https://www.vaultproject.io/) (via [bank-vaults](https://bank-vaults.dev/)) as secret store
- [Authentik](https://goauthentik.io/) for SSO / forward-auth (**`mocha`**)
- [SigNoz](https://signoz.io/) + [OpenTelemetry Operator](https://github.com/open-telemetry/opentelemetry-operator) for metrics, logs and traces
- [CrowdSec](https://www.crowdsec.net/) to filter traffic hitting the Ingress (**`mocha`**)
- [Cloudflare Tunnels](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) to expose services to the internet (**`turing`**)
- [Volsync](https://github.com/backube/volsync) to back up PVCs with restic (**`mocha`**)
- [Spegel](https://spegel.dev/) to share images between nodes (**`turing`**)
- [Reloader](https://github.com/stakater/Reloader) to restart workloads when a ConfigMap/Secret changes
- Cluster API ([KubeVirt](https://kubevirt.io/) + Talos providers) to run guest clusters on `mocha`

### Clusters

- [**Mocha**](https://github.com/qjoly/GitOps/tree/main/mocha) : single bare-metal node hosted by OVH (128GB RAM, 8 CPU, 2x512GB NVMe). Production cluster, also the management plane for guest clusters.
- [**Turing**](https://github.com/qjoly/GitOps/tree/main/turing) : cluster made of small devices (ARM and x86) at home. Local hosting, storage (Rook + NAS) and testing.

`cortado` and the standalone `kubevirt` cluster have been retired — the old configs live in the git history.

### Not Kubernetes

- [**Americano**](https://github.com/qjoly/GitOps/tree/main/americano) : a bare host running podman quadlets, reconciled by [Materia](https://github.com/stryan/materia) instead of ArgoCD. See [`americano/README.md`](./americano/README.md) for the branch trick that makes it work from a subdirectory.
- [`external/`](./external) : OTel collector and exporter units for machines outside the clusters (Proxmox hosts, the `affogato` backup box).

## Guest clusters on `mocha`

Instead of a second physical cluster for tests, `mocha` hosts [Cluster API](https://cluster-api.sigs.k8s.io/) guest clusters running as KubeVirt VMs — plain Talos + Cilium clusters, one values file each.

Two reasons to keep them around:

1. **Network isolation**: their pod/service CIDRs live inside the VMs, so they can overlap freely with the host cluster (and with each other).
2. **Configuration testing**: same core components as production, disposable.

Creating, destroying and adopting them is documented in [`mocha/clusters/README.md`](./mocha/clusters/README.md). The chart doing the work is [`qjoly/kubevirt-capi-easy`](https://github.com/qjoly/kubevirt-capi-easy). For the story of the previous (Omni-managed) KubeVirt setup, see [my article about Omni and Kubevirt](https://a-cup-of.coffee/blog/omni/).

## Usage

To use this repository, you need to have the Omni CLI installed. You can find the installation instructions [here](https://omni.siderolabs.com/how-to-guides/install-and-configure-omnictl).

Download the `omniconfig` file from the Omni instance and merge it with the one in your home directory.

```bash
omnictl config merge ./omniconfig.yaml
```

Then, you can deploy the cluster based on the MachineClass you have configured.

```bash
cd mocha
omnictl cluster template sync -f template.yaml
```

This will create a new cluster based on the configuration you have set in the `template.yaml` file. You can download the kubeconfig file using the following command:

```bash
omnictl kubeconfig --cluster mocha
```

Recurring operations (Vault unseal, guest cluster kubeconfig) are `mise` tasks:

```bash
mise tasks          # list them
mise run vault:status
```

## CI/CD

| Workflow | What it does |
|----------|--------------|
| `omni-template-sync.yaml` | Syncs the Omni cluster templates on every push to `main` (see below) |
| `materia-americano.yaml` | Republishes `americano/` to the root of the `americano` branch for Materia |
| `tangled-mirror.yaml` | Mirrors the repo to tangled |
| `page.yaml` | Builds and publishes the mkdocs site ([docs](https://qjoly.github.io/GitOps/)) |
| `spindle-image.yaml`, `abcdesktop-image.yaml`, `atcr-hold-image.yaml` | Build the container images for a few self-hosted apps |

### Automatic cluster template sync

The workflow `.github/workflows/omni-template-sync.yaml` runs `omnictl cluster template sync` automatically on every push to `main` that modifies files under `turing/` or `mocha/`.

A `detect` job inspects the diff and builds a matrix of changed clusters. A parallel `sync` job then syncs each one independently — touching only `mocha/` never triggers a `turing` sync, and a failure in one cluster does not block the other.

`archives/` is intentionally excluded from CI sync. More details in [`docs/github-actions.md`](./docs/github-actions.md).

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
    name: omni-mocha
contexts:
  - context:
      cluster: omni-mocha
      namespace: default
      user: omni-mocha-quentinj@une-pause-cafe.fr
    name: omni-mocha
current-context: omni-mocha
users:
- name: omni-mocha-quentinj@une-pause-cafe.fr
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      args:
        - oidc-login
        - get-token
        - --oidc-issuer-url=https://omni.home.une-tasse-de.cafe/oidc
        - --oidc-client-id=native
        - --oidc-extra-scope=cluster:mocha
      command: kubectl
      env: null
      provideClusterInfo: false
```
</details>
