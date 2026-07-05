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

## Telemetry collection

Each cluster runs the `k8s-infra` chart. It ships pod logs, host and kubelet
metrics, cluster metrics and Kubernetes events. The `global.clusterName` value sets
the `k8s.cluster.name` resource attribute on everything the agent sends, which is
how telemetry from each cluster is kept separate in the UI.

mocha talks to its collector in-cluster over plain HTTP:

```
otelCollectorEndpoint: http://signoz-otel-collector.signoz.svc.cluster.local:4318
```

The agent does not produce application traces on its own. To trace an application,
instrument it with an OpenTelemetry SDK and point it at the collector.

## Application metrics

Some applications ship their own metrics on top of what k8s-infra collects.

Traefik exports its metrics over OTLP (`metrics.otlp` in its Helm values). On mocha
it sends to the in-cluster collector; on other clusters it sends to the mTLS ingest
endpoint with a client certificate. Each Traefik tags its metrics with
`cluster=<name>` through `resourceAttributes`, which needs Traefik v3.5 or newer.

ArgoCD only exposes Prometheus metrics, so a Prometheus receiver added to the
k8s-infra deployment collector (`otelDeployment.config`) scrapes the ArgoCD metrics
services and forwards them, tagged with `cluster=mocha`.

The Traefik and ArgoCD dashboards both carry a `cluster` variable. `cluster` is a
resource attribute, so the dashboard filters reference it with an empty type
(`{"key":"cluster","type":""}`), not as a tag.

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

On mocha, secrets come from Vault through the argocd-vault-plugin. A remote cluster
without Vault or External Secrets can manage its mTLS client certificate with
cert-manager instead: a self-signed CA issues a client certificate, cert-manager
keeps both up to date, and no private key ever lands in the repository.

The certificate is mounted into the `k8s-infra` agent, and the collector config
points at it:

```
exporters:
  otlphttp:
    tls:
      cert_file: /mtls/tls.crt
      key_file: /mtls/tls.key
```

For mocha to accept a cluster's certificate, that cluster's CA (the public
certificate only) is added to mocha's `signoz-mtls-ca` secret. The `TLSOption`
accepts several CAs, one per cluster.

## Adding a new cluster

1. Deploy the `k8s-infra` chart on the cluster and set `global.clusterName` to its
   name.
2. Let cert-manager issue a CA and a client certificate for it.
3. Add the cluster's CA public certificate to mocha's `signoz-mtls-ca` secret.
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

## Alerting

Alerts go to Discord. SigNoz has no native Discord support, but Discord accepts
Slack-formatted payloads on the `/slack` suffix of a webhook URL. A Slack channel in
SigNoz pointing at `<discord-webhook>/slack` therefore works.

The webhook lives in Vault at `kv/discord` under the `webhook` property, with the
`/slack` suffix already included, and reaches the cluster through an ExternalSecret.

`alerting.yaml` holds two things:

- the ExternalSecret for the webhook,
- a Job (ArgoCD PostSync hook) that upserts the `discord` notification channel and
  the alert rules through the SigNoz API.

Alert rules use the SigNoz v5 rule schema (`queries` with a `spec` and a
`filter.expression`). The rule shipped here fires when ArgoCD reports out-of-sync
applications and notifies the `discord` channel.

To add an alert, append a rule object to the Job and re-sync, or create it in the UI
and pick the `discord` channel. To test the channel, use the "Test" button on it in
the UI, or SigNoz's `POST /api/v1/testChannel`.
