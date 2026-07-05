# Proxmox VE telemetry

Two Proxmox VE nodes forming a single PVE cluster: `homelab-proxmox-01` (192.168.0.181) and
`homelab-proxmox-02` (192.168.0.182). They are NOT managed by ArgoCD; these files are
versioned for traceability and are applied over SSH.

## Components (systemd, root)
- `otelcol-contrib` v0.155 (OpenTelemetry Collector) on each node: host metrics (cpu, memory,
  load, disk, filesystem, network, paging), pushing OTLP/HTTP to
  `signoz-ingest.mocha.thoughtless.eu` over mTLS.
- `prometheus-pve-exporter` (python venv `/opt/pve-exporter`) on `127.0.0.1:9221`, scraped by
  the collector on `proxmox-01` only. Because the two nodes share one PVE cluster, each
  exporter returns the whole cluster (VMs, LXC, storage), so scraping both would duplicate
  every PVE series. `proxmox-01` scrapes it; on `proxmox-02` the exporter is installed but
  disabled (standby, swap the scrape over if node 01 is down).

## mTLS
The client certificate lives in `/etc/otelcol/certs/{client.crt,client.key}`, signed by a
dedicated CA (`proxmox-ca`) whose public cert is added to mocha's `signoz-mtls-ca` secret
bundle (`mocha/system/signoz/otlp-mtls.yaml`). No inbound port is exposed; the collector only
pushes outbound.

## PVE API token
The exporter authenticates with a read-only token `otel@pve!monitoring` (role `PVEAuditor`),
created with `pveum`. The token value is NOT stored in this repo; put it in
`/etc/prometheus/pve.yml` (see `pve.yml.example`, chmod 600).

## Files
- `otelcol-config.proxmox-01.yaml` -> `/etc/otelcol/config.yaml` on node 01 (host + pve)
- `otelcol-config.proxmox-02.yaml` -> `/etc/otelcol/config.yaml` on node 02 (host only)
- `otelcol-contrib.service` -> `/etc/systemd/system/otelcol-contrib.service` (both)
- `pve-exporter.service` -> `/etc/systemd/system/pve-exporter.service` (both)
- `pve.yml.example` -> template for `/etc/prometheus/pve.yml`

Host metrics are tagged `k8s.cluster.name=proxmox-01` / `proxmox-02`; the PVE cluster metrics
are all tagged `proxmox-01` (single scraper) and carry a `node` label to tell nodes apart.

## Note (proxmox-02 DNS)
Node 02 had a stale resolver (`192.168.1.254`, wrong subnet); `/etc/resolv.conf` was pointed
at the gateway `192.168.0.1` so package/binary downloads resolve.
