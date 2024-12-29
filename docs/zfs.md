# ZFS

Since Talos doesn't support RAID yet, I use ZFS to create a RAIDZ2 pool with 3 disks. Once the pool is created, I use [local-path-provisionner](https://github.com/rancher/local-path-provisioner) to create persistent volumes on the mounted ZFS filesystem.

When I installed Talos on my server, I specified the `zfs` extension to download the Talos image with ZFS support.

I also had to enable the ZFS module in the kernel. Here is the patch to enable the ZFS module in the kernel:

```yaml
machine:
  kernel:
    modules:
      - name: zfs
```

Once Talos rebooted, I run a debug pod to create the ZFS pool:

```bash
kubectl -n kube-system debug -it --profile sysadmin --image=alpine node/{your-node}
```

To create the ZFS pool, we need to get the ID of the disk ( since name could change, we use the ID to identify the disk). We can use the `ls` command to list the disks:
```bash
/ # ls -lh /host/dev/disk/by-id/
total 0
lrwxrwxrwx    1 root     root           9 Dec 17 20:33 ata-HGST_HUS726020ALA610_K5H3U3ZA -> ../../sdc
lrwxrwxrwx    1 root     root          10 Dec 17 20:34 ata-HGST_HUS726020ALA610_K5H3U3ZA-part1 -> ../../sdc1
lrwxrwxrwx    1 root     root          10 Dec 17 20:33 ata-HGST_HUS726020ALA610_K5H3U3ZA-part9 -> ../../sdc9
lrwxrwxrwx    1 root     root           9 Dec 17 20:33 ata-HGST_HUS726020ALA610_K5H64MYA -> ../../sdd
lrwxrwxrwx    1 root     root          10 Dec 17 20:34 ata-HGST_HUS726020ALA610_K5H64MYA-part1 -> ../../sdd1
lrwxrwxrwx    1 root     root          10 Dec 17 20:33 ata-HGST_HUS726020ALA610_K5H64MYA-part9 -> ../../sdd9
lrwxrwxrwx    1 root     root           9 Dec 17 20:33 ata-HGST_HUS726020ALA610_K5HM8S6A -> ../../sdb
lrwxrwxrwx    1 root     root          10 Dec 17 20:34 ata-HGST_HUS726020ALA610_K5HM8S6A-part1 -> ../../sdb1
lrwxrwxrwx    1 root     root          10 Dec 17 20:33 ata-HGST_HUS726020ALA610_K5HM8S6A-part9 -> ../../sdb9
lrwxrwxrwx    1 root     root           9 Dec 17 20:33 ata-HGST_HUS726020ALA610_K5HPPLTA -> ../../sda
lrwxrwxrwx    1 root     root          10 Dec 17 20:33 ata-HGST_HUS726020ALA610_K5HPPLTA-part1 -> ../../sda1
lrwxrwxrwx    1 root     root          10 Dec 17 20:33 ata-HGST_HUS726020ALA610_K5HPPLTA-part2 -> ../../sda2
lrwxrwxrwx    1 root     root          10 Dec 17 20:33 ata-HGST_HUS726020ALA610_K5HPPLTA-part3 -> ../../sda3
lrwxrwxrwx    1 root     root          10 Dec 17 20:33 ata-HGST_HUS726020ALA610_K5HPPLTA-part4 -> ../../sda4
lrwxrwxrwx    1 root     root          10 Dec 17 20:33 ata-HGST_HUS726020ALA610_K5HPPLTA-part5 -> ../../sda5
lrwxrwxrwx    1 root     root          10 Dec 17 20:33 ata-HGST_HUS726020ALA610_K5HPPLTA-part6 -> ../../sda6
```

Before creating the pool, we need to clean the disks by using the `wipefs` command, please be careful, this command will erase all the data on the disk:

```bash
apk add wipefs
wipefs /dev/sdb --all --force
wipefs /dev/sdc --all --force
wipefs /dev/sdd --all --force
apk add xfsprogs
mkfs.xfs /dev/sdb
mkfs.xfs /dev/sdc
mkfs.xfs /dev/sdd
```

Then, we can create the pool:

```bash
chroot /host zpool create -f \
-o ashift=12 \
-O mountpoint="/var/zfs_pool" \
-O xattr=sa \
-O compression=zstd \
-O acltype=posixacl \
-O atime=off \
hdd \
raidz2 \
/dev/disk/by-id/ata-HGST_HUS726020ALA610_K5H3U3ZA \
/dev/disk/by-id/ata-HGST_HUS726020ALA610_K5H64MYA \
/dev/disk/by-id/ata-HGST_HUS726020ALA610_K5HM8S6A 
```

Once the pool is created, we can deploy the local-path-provisionner:

```bash
# kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- github.com/rancher/local-path-provisioner/deploy?ref=v0.0.26
patches:
- patch: |-
    kind: ConfigMap
    apiVersion: v1
    metadata:
      name: local-path-config
      namespace: local-path-storage
    data:
      config.json: |-
        {
                "nodePathMap":[
                {
                        "node":"DEFAULT_PATH_FOR_NON_LISTED_NODES",
                        "paths":["/var/zfs_pool"]
                }
                ]
        }    
- patch: |-
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: local-path
      annotations:
        storageclass.kubernetes.io/is-default-class: "true"    
- patch: |-
    apiVersion: v1
    kind: Namespace
    metadata:
      name: local-path-storage
      labels:
        pod-security.kubernetes.io/enforce: privileged    
```

You should now be able to generate PVC on the ZFS pool.