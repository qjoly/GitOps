# Welcome aboard!

This is a collection of notes and guides that I have written to help me remember how to do things. I hope you find them useful too. Keep in mind that everything here is a work in progress and that it's mostly for personal use, so it might not be the best way to do things, however, many choices are made with ease of use in mind.

First things first, let's explain what a CloudLab is.

## What the heck is a CloudLab?

In opposition to a HomeLab, a CloudLab a server rented from a cloud provider. It's a great way to experiment with new technologies without the need to buy hardware and deal with the noise and heat of the servers.

In my personal case, I have both a Homelab and a CloudLab. I use the CloudLab to test new technologies and the Homelab to host sensitive data and services (clusters `home` is the name of my Homelab cluster, `cortado` and `arabica` are CloudLab clusters).

I have 2 n100 servers at home, both are running Proxmox and are connected to a 1G switch as well as my NAS.s
![alt text](./img/sweet-home-lab.png)

*Sorry cable management enthusiasts, I'm not there yet.*

## Which technologies are used?

Like many people in the k8s-at-home community, I use Kubernetes to manage my services and prioritize Helm charts to deploy them. But many services / applications doesn't have a Helm chart (or the one provided doesn't respect my requirements) so I chose [to write my own templates](https://github.com/RubxKube/common-charts/) (If you start looking at my configuration, you will sometimes see `common-charts` instead of the official Helm chart).

To install and managed my Kubernetes cluster, I use [Talos](https://talos.dev/), a modern OS for Kubernetes. It's a great way to have a minimal OS that is easy to manage and secure. On top of that, I also have [Omni](https://omni.siderolabs.com/tutorials/getting_started/) to manage my cluster. Omni allows me to manage many clusters from a single interface and provides features like gRPC Proxy (to access the Kubernetes API of all clusters, directly from Omni and by using a standard Kubeconfig, [e.g. here](https://github.com/qjoly/GitOps/blob/750b83bf148b64d17f8af15213b78c26335a41f8/cortado/kubeconfig)), RBAC, Deployments, and more.

All Omni templates are stored in this repository (e.g. [here](https://github.com/qjoly/GitOps/blob/750b83bf148b64d17f8af15213b78c26335a41f8/cortado/template.yaml)) and are applied with `omnictl`.

Here are just a few of the technologies and applications I use :
- [**Omni** (Self-hosted)](https://www.siderolabs.com/platform/saas-for-kubernetes/) : Manage all nodes between clusters and regions.
- [Cilium](https://cilium.io/) as CNI and LB (ARP mode)
- [ArgoCD](https://argoproj.github.io/argo-cd/) to manage the GitOps workflow
- [Nginx Ingress Controller](https://kubernetes.github.io/ingress-nginx/) for Ingress management (and [Istio](https://istio.io/) deployed on some clusters)
- [Cert Manager](https://cert-manager.io/) for TLS certificates.
- [Longhorn](https://longhorn.io/) for storage based on nodes disks (**Only on the `home` cluster**).
- [External Secrets](https://external-secrets.io/latest/) to fetch secrets from a remote store.
- [Vault](https://www.vaultproject.io/) as a secret store to store secrets.
- [Cloudflare Tunnels](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) to expose services to the internet (**Only on the `home` cluster**).
- [ZFS](https://openzfs.github.io/openzfs-docs/) + [Local-Path-Provisioner](https://github.com/rancher/local-path-provisioner) to create persistent volumes on the mounted ZFS filesystem (**Only on CloudLab cluster**).
- [Volsync](https://github.com/backube/volsync) to create backup and send backup (using restic) to a minio server (**Only on CloudLab cluster**).