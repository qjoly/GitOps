# Welcome aboard!

This is a collection of notes and guides that I have written to help me remember how to do things. I hope you find them useful too. Keep in mind that everything here is a work in progress and that it's mostly for personal use, so it might not be the best way to do things, however, many choices are made with ease of use in mind.

First things first, let's explain what a HomeLab is.

## What the heck is a CloudLab?

In opposition to a HomeLab, a CloudLab a server rented from a cloud provider. It's a great way to experiment with new technologies without the need to buy hardware and deal with the noise and heat of the servers.

In my personal case, I have both a Homelab and a CloudLab. I use the CloudLab to test new technologies and the Homelab to host sensitive data and services.

I have 2 n100 servers at home, both are running Proxmox and are connected to a 1G switch as well as my NAS.s
![alt text](./img/sweet-home-lab.png)

*Sorry cable management enthusiasts, I'm not there yet.*

## Which technologies are used?

Like many people in the k8s-at-home community, I use Kubernetes to manage my services and prioritize Helm charts to deploy them. But many services / applications doesn't have a Helm chart (or the one provided doesn't respect my requirements) so I chose [to write my own templates](https://github.com/RubxKube/common-charts/) (If you start looking at my configuration, you will sometimes see `common-charts` instead of the official Helm chart).

To install and managed my Kubernetes cluster, I use [Talos](https://talos.dev/), a modern OS for Kubernetes. It's a great way to have a minimal OS that is easy to manage and secure. On top of that, I also have [Omni](https://omni.siderolabs.com/tutorials/getting_started/) to manage my cluster. Omni allows me to manage many clusters from a single interface and provides features like gRPC Proxy (to access the Kubernetes API of all clusters, directly from Omni and by using a standard Kubeconfig, [e.g. here](https://github.com/qjoly/GitOps/blob/750b83bf148b64d17f8af15213b78c26335a41f8/cortado/kubeconfig)), RBAC, Deployments, and more.

All Omni templates are stored in this repository (e.g. [here](https://github.com/qjoly/GitOps/blob/750b83bf148b64d17f8af15213b78c26335a41f8/cortado/template.yaml)) and are applied with `omnictl`.


