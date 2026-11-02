# Guest clusters

> [!WARNING]
> Nothing in this directory runs. It belongs to the KubeVirt + Talos setup,
> which did not survive the move of `mocha` to Corium: KubeVirt, CDI and the
> Talos CAPI providers are not installed, `talos-poc` is gone, and
> [`../bootstrap/as-clusters.yml`](../bootstrap/as-clusters.yml) is not applied.

## Current approach: Virtink + Kamaji

The guest cluster in progress is [`../apps/kube-lab`](../apps/kube-lab): a
control plane hosted by Kamaji as pods on `mocha`, workers as Virtink VMs, and
Cilium pushed into the guest by CAAPH.

Installed on `mocha`:

- Virtink v0.17.0 ([`../system/virtink`](../system/virtink))
- CAPI Virtink provider v0.7.0 ([`../system/capi-provider-virtink`](../system/capi-provider-virtink))
- CAPI Kamaji control-plane provider v0.21.0 ([`../system/capi-cp-kamaji`](../system/capi-cp-kamaji))

Missing, so `kube-lab` fails to sync: the CAPI core, the kubeadm bootstrap
provider, CAAPH and the Kamaji operator.

The guest pod CIDR must not overlap `mocha`'s pod CIDR (`10.244.0.0/16`): the
worker VMs sit on `mocha`'s pod network.

## Old approach: KubeVirt + Talos

`values/` holds one file per cluster for the
[`qjoly/kubevirt-capi-easy`](https://github.com/qjoly/kubevirt-capi-easy) chart
(`charts/kubevirt-talos`), and the `mocha-guest-clusters` ApplicationSet would
create one `cluster-<name>` Application per file. Bringing it back requires
KubeVirt + CDI, the `kubevirt`, `talos`, `helm` and `in-cluster` CAPI providers,
and the `talos` `VirtualMachineClusterPreference`.

On `openebs-lvmpv`, keep `rootVolumeMode: Filesystem`: a raw `Block` volume
makes the CDI importer fail with `cannot open /dev/cdi-block-volume: Permission
denied`.
