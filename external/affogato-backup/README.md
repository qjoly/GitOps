# affogato backup server (ZFS) telemetry

External AlmaLinux server `ns31121163.ip-51-83-141.eu` (hostname `Affogato`) running a ZFS
`datapool`. It is NOT managed by ArgoCD; these files are versioned for traceability and are
applied over SSH.

## Components (systemd, root)
- `zfs_exporter` v2.3.12 (github.com/pdf/zfs_exporter) on `127.0.0.1:9134` for ZFS pool and
  dataset metrics.
- `otelcol-contrib` (OpenTelemetry Collector) collecting host metrics and scraping the local
  zfs_exporter, pushing OTLP/HTTP to `signoz-ingest.mocha.thoughtless.eu` over mTLS.

## mTLS
The client certificate lives in `/etc/otelcol/certs/{client.crt,client.key}`, signed by a
dedicated CA (`affogato-backup-ca`) whose public cert is added to mocha's `signoz-mtls-ca`
secret bundle (`mocha/system/signoz/otlp-mtls.yaml`). No inbound port is exposed; the
collector only pushes outbound.

## Files
- `otelcol-config.yaml` -> `/etc/otelcol/config.yaml`
- `zfs_exporter.service` -> `/etc/systemd/system/zfs_exporter.service`
- `otelcol-contrib.service` -> `/etc/systemd/system/otelcol-contrib.service`

Metrics are tagged `k8s.cluster.name=affogato`.
