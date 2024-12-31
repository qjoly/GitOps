## Backup system

When I created the `cortado` cluster (which is a single node cluster), I used a ZFS zpool (created manually) and [local-path-provisionner](https://github.com/rancher/local-path-provisioner) to create persistent volumes on the mounted ZFS filesystem.

To backup the data, I use [volsync](https://github.com/backube/volsync) to create backup and send backup (using restic) to a minio server.

I will have a restic repository per backup source.

### Create a restic repository
```bash
export AWS_ACCESS_KEY_ID=YOUR_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=YOUR_SECRET_KEY
export RESTIC_PASSWORD=REPOSITORY_PASSWORD
export RESTIC_REPOSITORY=s3:http://MINIO_URL:9000/BUCKET
```

From your workstation, create the repository
```bash
restic init
```


Then, create a secret in the cluster with the credentials to access the repository
```bash
kubectl create secret generic -n kube-system restic-credentials \
  --from-literal=AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
  --from-literal=AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
  --from-literal=RESTIC_PASSWORD=$RESTIC_PASSWORD \
  --from-literal=RESTIC_REPOSITORY=$RESTIC_REPOSITORY
```

<details>
<summary>Use an ExternalSecret</summary>

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: restic-credentials
  namespace: komga
spec:
  refreshInterval: "30s"
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: restic-credentials
  data:
    - secretKey: AWS_ACCESS_KEY_ID
      remoteRef:
        key: restic
        property: AWS_ACCESS_KEY_ID
    - secretKey: AWS_SECRET_ACCESS_KEY
      remoteRef:
        key: restic
        property: AWS_SECRET_ACCESS_KEY
    - secretKey: RESTIC_PASSWORD
      remoteRef:
        key: restic
        property: RESTIC_PASSWORD
    - secretKey: RESTIC_REPOSITORY
      remoteRef:
        key: restic
        property: RESTIC_REPOSITORY
```

</details>


You can now create a `ReplicationSource` to backup a specific PVC.

```yaml
apiVersion: volsync.backube/v1alpha1
kind: ReplicationSource
metadata:
  name: komga
spec:
  # The PVC name to backup
  sourcePVC: komga-data
  trigger:
    schedule: "*/5 * * * *"
  restic:
    pruneIntervalDays: 7
    repository: restic-credentials
    retain:
      hourly: 6
      daily: 5
      weekly: 4
      monthly: 2
      yearly: 1
    copyMethod: Direct
```

From your workstation, you can see backups

```bash
$ restic snapshots
repository f8c8acc2 opened (version 2, compression level auto)
created new cache in /Users/qjoly/Library/Caches/restic
ID        Time                 Host        Tags        Paths  Size
-----------------------------------------------------------------------
7ebbffdd  2024-12-24 09:38:48  volsync                 /data  1.689 MiB
8a7574a4  2024-12-24 09:55:06  volsync                 /data  1.689 MiB
9b5b7a1a  2024-12-24 10:00:07  volsync                 /data  1.689 MiB
-----------------------------------------------------------------------
3 snapshots
```

### Restore a backup

Eh, eh, this is still a work in progress. I will update this section when I have more information.

![](https://media.tenor.com/udq1uD9WHSQAAAAM/oops.gif)