# Guest clusters (KubeVirt + Talos)

GitOps-managed [Cluster API](https://cluster-api.sigs.k8s.io/) guest clusters
running as KubeVirt VMs on top of `mocha`. Each cluster is a plain Talos +
Cilium Kubernetes cluster.

The chart doing the work lives in
[`qjoly/kubevirt-capi-easy`](https://github.com/qjoly/kubevirt-capi-easy)
(`charts/kubevirt-talos`). Here we only keep the per-cluster values.

## Create a cluster

1. Drop a file in [`values/`](./values/) — one file per cluster. The name of
   `talosCluster.name` becomes both the cluster name and its namespace.

   ```yaml
   # values/dev-quentin.yaml
   global:
     namespace: dev-quentin
   talosCluster:
     name: dev-quentin
     talosImageURL: https://factory.talos.dev/image/<hash>/v1.13.7/openstack-amd64.raw.xz
     workerMachineCount: 2
   ```

   Everything not set falls back to the chart defaults
   (`charts/kubevirt-talos/values.yaml`).

2. Commit. The `mocha-guest-clusters` ApplicationSet
   ([`../bootstrap/as-clusters.yml`](../bootstrap/as-clusters.yml)) picks the
   file up and creates an Argo CD `Application` named `cluster-<name>`.

## Destroy a cluster

Delete its file and commit. Argo CD prunes the `Application`, which deletes the
`Cluster` object and lets CAPI tear the VMs down.

## Run several

Add several files. The ApplicationSet fans out, one `Application` per file.
Pod/Service CIDRs live *inside* each guest's VMs, so they can safely be
identical across clusters — no need to keep them disjoint.

## Get the kubeconfig

```bash
mise run talos-poc:kubeconfig   # see ../../mise.toml (parameterised by env)
```

## Prerequisites (management plane, already on `mocha`)

- CAPI providers: `kubevirt` (infra), `talos` (control-plane + bootstrap),
  `helm` (addon), `in-cluster` (ipam).
- KubeVirt + CDI, a `longhorn` StorageClass, and the `talos`
  `VirtualMachineClusterPreference` (`kubevirt-capi-easy/talosVMCP.yaml`).

## Adopting an existing, hand-applied cluster

`talos-poc` was first created manually. Before letting the ApplicationSet
auto-sync an already-running cluster, review the Argo CD diff: resource names
carry the `talosCode` suffix, so a mismatch (e.g. `t195` vs `t1137`) makes CAPI
roll new machine templates. These values pin Talos `v1.13.7` (`t1137`), so
syncing a cluster still on an older Talos build will roll its VMs onto the new
image — intended here, but do it deliberately. Either set
`talosCode`/`talosVersion` to match the live cluster or recreate it from scratch.
