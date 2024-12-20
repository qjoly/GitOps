
- Install ZFS (by adding the siderolabs/zfs extension)
- Enable the ZFS module 


```yaml
machine:
  kernel:
    modules:
      - name: zfs
```

talosctl ls -n {your-node} /dev/disk/by-id
kubectl -n kube-system debug -it --profile sysadmin --image=alpine node/{your-node}


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