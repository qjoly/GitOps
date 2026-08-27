# tranquil-pds

AT Protocol Personal Data Server ([tranquil.farm/tranquil-pds](https://tangled.org/tranquil.farm/tranquil-pds)),
a single Rust binary. Deployed as app + PostgreSQL. The built-in `ripple` cache
(in-process) and `filesystem` blob backend are used, so no Valkey or MinIO is needed.
The app runs its own DB migrations on first boot.

## Bootstrap (out-of-band, before first sync)

### 1. atcr.io pull secret

The image lives in a private atcr.io repo. The `atcr-pull` dockerconfigjson secret
must exist in the `tranquil-pds` namespace with credentials able to pull
`atcr.io/tranquil.farm/tranquil-pds`:

```sh
kubectl -n tranquil-pds create secret docker-registry atcr-pull \
  --docker-server=atcr.io \
  --docker-username='<handle>' \
  --docker-password='<app-password>'
```

### 2. Application secret

Generate the secrets (each ≥ 32 chars) and create `tranquil-pds-secrets`. The
password inside `DATABASE_URL` must match `DB_PASSWORD` (consumed by Postgres):

```sh
DB_PASSWORD="$(openssl rand -base64 24)"
kubectl -n tranquil-pds create secret generic tranquil-pds-secrets \
  --from-literal=PDS_HOSTNAME='pds.mocha.thoughtless.eu' \
  --from-literal=DATABASE_URL="postgres://tranquil_pds:${DB_PASSWORD}@tranquil-pds-db:5432/pds" \
  --from-literal=DB_PASSWORD="${DB_PASSWORD}" \
  --from-literal=JWT_SECRET="$(openssl rand -base64 48)" \
  --from-literal=DPOP_SECRET="$(openssl rand -base64 48)" \
  --from-literal=MASTER_KEY="$(openssl rand -base64 48)"
```

> `MASTER_KEY` encrypts account keys — losing it means losing every account. Back it up.

## DNS / TLS

User handles are served as subdomains, so the Ingress publishes both
`pds.mocha.thoughtless.eu` and `*.pds.mocha.thoughtless.eu`, and cert-manager
issues a single wildcard certificate via the `cloudflare` (DNS-01) ClusterIssuer.
external-dns creates both records; the wildcard is published DNS-only (not proxied).

The PDS must be reachable from the public internet for AT Protocol federation.
