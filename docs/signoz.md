# SigNoz

SigNoz is the observability backend for the homelab. It stores metrics, logs and
traces, and it runs on the **mocha** cluster. Every cluster ships its telemetry to
this single instance over OpenTelemetry, and each one is tagged with its name so
the data can be told apart.

## Architecture

The core stack lives on mocha under `mocha/system/signoz/` and is deployed by the
`signoz` Helm chart. It bundles ClickHouse (storage), Zookeeper, an OpenTelemetry
collector and the web UI.

- The UI is exposed at `signoz.mocha.thoughtless.eu` through a Traefik ingress with
  a cert-manager certificate.
- ClickHouse persists its data on the `openebs-lvmpv` storage class.
- Telemetry is collected by the `k8s-infra` agent, one per cluster.

mocha collects its own telemetry through the in-cluster collector. Other clusters
push to an OTLP endpoint exposed over the internet and protected with mTLS.

## Repository layout

| Path | Purpose |
| --- | --- |
| `mocha/system/signoz/signoz.yaml` | SigNoz core (ClickHouse, collector, UI) |
| `mocha/system/signoz/k8s-infra.yaml` | Agent collecting mocha's own telemetry |
| `mocha/system/signoz/otlp-ingress.yaml` | Public OTLP/HTTP ingress for other clusters |
| `mocha/system/signoz/otlp-mtls.yaml` | mTLS: trusted client CAs and Traefik TLSOption |
| `mocha/system/signoz/dashboard-provisioner.yaml` | Job importing dashboards through the API |
| `mocha/system/signoz/dashboards/` | Dashboard definitions (JSON) |
| `turing/system/signoz-k8s-infra/` | turing's agent + mTLS client certificate |

## Telemetry collection

Each cluster runs the `k8s-infra` chart. It ships pod logs, host and kubelet
metrics, cluster metrics and Kubernetes events. The `global.clusterName` value sets
the `k8s.cluster.name` resource attribute on everything the agent sends, which is
how telemetry from mocha and turing is kept separate in the UI.

mocha talks to its collector in-cluster over plain HTTP:

```
otelCollectorEndpoint: http://signoz-otel-collector.signoz.svc.cluster.local:4318
```

The agent does not produce application traces on its own. To trace an application,
instrument it with an OpenTelemetry SDK and point it at the collector.

## Exposing SigNoz to other clusters

The collector is exposed at `signoz-ingest.mocha.thoughtless.eu` (OTLP/HTTP, port
4318) through a Traefik ingress. The endpoint is protected with mTLS: a client has
to present a certificate signed by a CA that mocha trusts, otherwise the TLS
handshake is refused.

The trust and enforcement live in `otlp-mtls.yaml`:

- a `Secret` (`signoz-mtls-ca`) holding the CA certificates under `tls.ca`,
- a Traefik `TLSOption` set to `RequireAndVerifyClientCert`,
- the ingress references the option with the
  `traefik.ingress.kubernetes.io/router.tls.options` annotation.

## Client certificates

On mocha, secrets come from Vault through the argocd-vault-plugin. turing has
neither Vault nor External Secrets, so its mTLS client certificate is managed by
cert-manager, which it already runs.

`turing/system/signoz-k8s-infra/mtls.yaml` sets up a self-signed CA and issues a
client certificate from it. cert-manager keeps both up to date and never writes a
private key to the repository. The certificate is mounted into the `k8s-infra`
agent, and the collector config points at it:

```
exporters:
  otlphttp:
    tls:
      cert_file: /mtls/tls.crt
      key_file: /mtls/tls.key
```

For mocha to accept turing's certificate, turing's CA (the public certificate only)
is copied into mocha's `signoz-mtls-ca` secret.

## Adding a new cluster

1. Copy `turing/system/signoz-k8s-infra/` and set `global.clusterName` to the new
   cluster's name.
2. Let cert-manager issue a per-cluster CA and client certificate.
3. Add the new cluster's CA public certificate to mocha's `signoz-mtls-ca` secret
   (the `TLSOption` accepts several CAs).
4. Sync both clusters.

## Dashboards

Dashboards are versioned as JSON under `mocha/system/signoz/dashboards/` and
imported by a Job (`dashboard-provisioner.yaml`) that runs as an ArgoCD PostSync
hook. The Job talks to the SigNoz API and skips dashboards that already exist, so
it is safe to run on every sync.

The Job authenticates with a SigNoz API key. Create one in the UI under
**Settings → API Keys** and store it in Vault at `kv/signoz` under the `api_key`
property; External Secrets exposes it to the Job.

To add a dashboard, drop its JSON file in the `dashboards/` directory and add it to
the `configMapGenerator` in `kustomization.yaml`. The next sync imports it.
