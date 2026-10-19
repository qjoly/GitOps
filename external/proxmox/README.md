# Proxmox VE telemetry

One live Proxmox VE node, `homelab-proxmox-01` (192.168.0.181), running PVE 8.4. It is NOT
managed by ArgoCD; these files are versioned for traceability and are applied over SSH.

A second node, `homelab-proxmox-02` (192.168.0.182), is currently **offline** — see below.

## Components (systemd, root)
- `otelcol-contrib` v0.155 (OpenTelemetry Collector): host metrics (cpu, memory, load, disk,
  filesystem, network, paging), pushing OTLP/HTTP to `signoz-ingest.mocha.thoughtless.eu`
  over mTLS.
- `prometheus-pve-exporter` (python venv `/opt/pve-exporter`) on `127.0.0.1:9221`, scraped by
  the collector.

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
- `otelcol-config.proxmox-02.yaml` -> `/etc/otelcol/config.yaml` on node 02 (host only),
  kept for the day node 02 comes back; applied nowhere right now
- `otelcol-contrib.service` -> `/etc/systemd/system/otelcol-contrib.service`
- `pve-exporter.service` -> `/etc/systemd/system/pve-exporter.service`
- `pve.yml.example` -> template for `/etc/prometheus/pve.yml`

Host metrics are tagged `k8s.cluster.name=proxmox-01` / `proxmox-02`; PVE metrics carry a
`node` label.

## No PVE cluster

The two nodes were once described as a single PVE cluster, which is no longer true:
`pvecm status` on node 01 reports no `corosync.conf`, and `/etc/pve/nodes/` holds only
`homelab-proxmox-01`. Each node is therefore standalone, and its exporter returns only its
own guests and storage — there is no longer any duplication to avoid, so node 02 will need
its own enabled exporter rather than the standby arrangement the cluster justified.

This is also why node 02 going away was invisible for so long: the `Proxmox node down` alert
reads `pve_up`, and with no cluster node 01's exporter simply stopped publishing a series for
node 02 instead of publishing it as down. Absence is now covered separately by the
`Proxmox-01 / Proxmox-02 host not reporting` rules in
`mocha/system/signoz-resources/rules/`, which alert on missing host metrics.

## Node 02 offline

`homelab-proxmox-02` has sent nothing since 2026-09-30. It answers neither SSH nor ICMP, and
from node 01 on the same segment its ARP entry goes to `FAILED` and TCP/22 returns *no route
to host* — the host is down or off the network, not just its collector. Bringing it back
needs physical or out-of-band access.

Its stale resolver is worth remembering when it does come back: `/etc/resolv.conf` pointed at
`192.168.1.254`, the wrong subnet, and was repointed at the gateway `192.168.0.1` so package
and binary downloads resolve.
