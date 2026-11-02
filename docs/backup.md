# Backup

Backups run on `mocha` as CronJobs defined in [`mocha/system/backup/`](https://github.com/qjoly/GitOps/tree/main/mocha/system/backup). Each job writes a dump to an `emptyDir`, then a `restic` container pushes it to BunnyCDN S3 and prunes old snapshots (7 daily, 4 weekly, 6 monthly).

| CronJob | Namespace | Schedule | What | Repository |
|---|---|---|---|---|
| `authentik-pgdump` | `authentik` | `30 0 * * *` | `pg_dump` of Authentik | `mocha-coffee/authentik-postgres` |
| `matomo-db-dump` | `matomo` | `0 1 * * *` | MariaDB dump | `mocha-coffee/matomo-db` |
| `toutou-db-dump` | `toutou` | `15 1 * * *` | database dump | `mocha-coffee/toutou-db` |
| `tranquil-pds-db-dump` | `tranquil-pds` | `30 1 * * *` | database dump | `mocha-coffee/tranquil-pds-db` |
| `openbao-snapshot` | `bank-vaults` | `0 */6 * * *` | OpenBao raft snapshot | `mocha-coffee/openbao-raft` |

Repositories live under `s3:https://de-s3.storage.bunnycdn.com/`. A job initialises its repository on the first run.

## Credentials

The S3 keys and the restic password are in Vault under `kv/restic` (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `RESTIC_PASSWORD`). Each job has its own ExternalSecret (`restic-<job>`) that adds the `RESTIC_REPOSITORY` of that job.

## Add a backup

Copy one of the blocks in `logical-dumps.yaml` (ExternalSecret + CronJob), change the namespace, the dump command, the repository path and the `--tag`, then commit.

## Restore

```bash
export VAULT_CONTEXT=mocha-corium
export AWS_ACCESS_KEY_ID=$(mise run vault:kv get -field=AWS_ACCESS_KEY_ID kv/restic)
export AWS_SECRET_ACCESS_KEY=$(mise run vault:kv get -field=AWS_SECRET_ACCESS_KEY kv/restic)
export RESTIC_PASSWORD=$(mise run vault:kv get -field=RESTIC_PASSWORD kv/restic)
export RESTIC_REPOSITORY=s3:https://de-s3.storage.bunnycdn.com/mocha-coffee/matomo-db

restic snapshots
restic restore latest --target ./restore
```

## PVC backups with VolSync

VolSync is installed (`mocha/system/storage/volsync.yaml`) but no PVC is backed up with it yet. [`knot.yaml`](https://github.com/qjoly/GitOps/blob/main/mocha/system/backup/knot.yaml) holds the ReplicationSources for knot; it stays out of the kustomization until the knot PVCs move to `openebs-lvmpv-thin`, because openebs-lvm refuses the `Direct` copy method and only thin volumes can be snapshotted.
