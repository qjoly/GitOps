
<p align="center">
    <img src="https://avatars.githubusercontent.com/u/82603435?v=4" width="140px" alt="Helm LOGO"/>
    <br>
    <a href="https://a-cup-of.coffee"><img src="https://readme-typing-svg.herokuapp.com?font=Fira+Code&pause=1000&center=true&vCenter=true&width=435&lines=Homelab+made+simple;Talos+go+brrrrr;GitOps+FTW;No+inspiration+for+what+I'm+going+to+write+here" alt="Typing SVG" /></a>
</p>

<div align="center">

  [![Blog](https://img.shields.io/badge/Blog-blue?style=for-the-badge&logo=buymeacoffee&logoColor=white)](https://a-cup-of.coffee/)
  [![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.31.3-blue?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kubernetes.io/)
  [![Linux](https://img.shields.io/badge/Talos-v1.8.3-blue?style=for-the-badge&logo=linux&logoColor=white)](https://talos.dev/)

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
- [Nginx Ingress Controller](https://kubernetes.github.io/ingress-nginx/) for Ingress management (and [Istio](https://istio.io/) deployed on some clusters)
- [Cert Manager](https://cert-manager.io/) for TLS certificates.
- [Longhorn](https://longhorn.io/) for storage based on nodes disks.
- ~~[Reflector](https://github.com/emberstack/kubernetes-reflector/blob/main/README.md) to sync secrets across namespaces (requirement for External Secrets + Vault).~~ (Removed 16/12/2024)
- [External Secrets](https://external-secrets.io/latest/) to fetch secrets from a remote store.
- [Vault](https://www.vaultproject.io/) as a secret store to store secrets.
- [Cloudflare Tunnels](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) to expose services to the internet.

### Cluster

- **Lungo** : A cluster based on virtual machines on a Proxmox server hosted by OVH.
- **Home** (Quite original, right?) : A cluster based on small devices (ARM and x86) at home.
- **Arabica** (:warning: WIP) : Yet another cluster based on virtual machines on a Proxmox server hosted by OVH.

## Usage

To use this repository, you need to have the Omni CLI installed. You can find the installation instructions [here](https://omni.siderolabs.com/how-to-guides/install-and-configure-omnictl).

Download the `omniconfig` file from the Omni instance and merge it with the one in your home directory.

```bash
omnictl config merge ./omniconfig.yaml
```

Then, you can deploy the cluster based on the MachineClass you have configured.

```bash
cd lungo
omnictl cluster template sync -f template.yaml
```

This will create a new cluster based on the configuration you have set in the `template.yaml` file. You can download the kubeconfig file using the following command:

```bash
omnictl kubeconfig --cluster lungo
```

<details>
<summary>Example of kubeconfig file</summary>

```yaml
apiVersion: v1
kind: Config
clusters:
  - cluster:
      server: https://omni.home.une-tasse-de.cafe:8100/
    name: omni-lungo
contexts:
  - context:
      cluster: omni-lungo
      namespace: default
      user: omni-lungo-quentinj@une-pause-cafe.fr
    name: omni-lungo
current-context: omni-lungo
users:
- name: omni-lungo-quentinj@une-pause-cafe.fr
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      args:
        - oidc-login
        - get-token
        - --oidc-issuer-url=https://omni.home.une-tasse-de.cafe/oidc
        - --oidc-client-id=native
        - --oidc-extra-scope=cluster:lungo
      command: kubectl
      env: null
      provideClusterInfo: false
```
</details>