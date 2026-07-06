---
name: signoz
description: Manage the self-hosted SigNoz observability stack in this GitOps repo. Use when creating or editing SigNoz dashboards, wiring application metrics into SigNoz (Traefik, ArgoCD, other Prometheus/OTLP sources), configuring alerting and notification channels (Discord), or debugging why a dashboard variable filter does not work. Covers the non-obvious formats SigNoz v0.13x expects.
---

# SigNoz on this cluster

SigNoz runs on the **mocha** cluster (`mocha/system/signoz/`), deployed by the `signoz`
Helm chart via ArgoCD. Other clusters ship telemetry to it over OTLP. Every source is
tagged with `k8s.cluster.name` so data can be told apart.

Kube contexts: `omni-mocha` (SigNoz host) and `omni-turing`. The SigNoz API key lives in
Vault at `kv/signoz#api_key`, exposed to the `signoz` namespace as the `signoz-api-key`
secret. Call the API with the header `SIGNOZ-API-KEY: <key>` against
`http://signoz.signoz.svc.cluster.local:8080`.

## The dashboard variable filter gotcha (most important)

SigNoz v0.13x applies query filters from the **`filter.expression`** field (a string),
NOT from the legacy `filters.items` array. A dashboard whose filters only live in
`filters.items` will render, but **variables are never substituted and the filter is
silently ignored** (every value shows the cluster-wide total). This wasted a lot of time.

Every builder query must carry a `filter` object:

```json
"filter": { "expression": "k8s.cluster.name IN $k8s.cluster.name AND namespace = $namespace" }
```

Rules for the expression string:
- Variable reference: `key IN $varname` or `key = $varname` (no quotes around `$var`).
- Literal value: `key = 'value'` (single quotes).
- Join clauses with ` AND `.
- Keys with dots are fine: `k8s.cluster.name IN $k8s.cluster.name`.

Keep `filters.items` too (some UI code still reads it), but the expression is what filters.

## Cluster selector on a dashboard

To make a `k8s.cluster.name` selector that actually discriminates:

1. The metrics must carry the `k8s.cluster.name` resource attribute (see next section).
   Use `k8s.cluster.name`, the standard OTel key, not a custom `cluster` key: SigNoz's
   built-in dashboards use `k8s.cluster.name` and it behaves correctly.
2. Add a DYNAMIC variable. Its `id` and `key` MUST be a valid UUID. A made-up non-UUID id
   breaks the variable-to-filter binding and the filter is ignored:

```json
"id": "4349d5be-eea6-41d2-9c8f-853ca85f018d",
"name": "k8s.cluster.name",
"type": "DYNAMIC",
"dynamicVariablesAttribute": "k8s.cluster.name",
"dynamicVariablesSource": "All telemetry",
"multiSelect": false, "showALLOption": true, "sort": "DISABLED"
```

3. Add the filter to each query's `filter.expression`:
   `k8s.cluster.name IN $k8s.cluster.name`.

The simplest way to get a working dashboard is to copy the query/variable/filter shape
from a built-in k8s-infra dashboard (for example the "Kubernetes Node Metrics" one), which
uses the modern format: `aggregations: [{metricName, timeAggregation, spaceAggregation,
reduceTo, temporality}]` plus `filter.expression`. Old community dashboards use the legacy
`aggregateAttribute` + `filters.items` shape and their variable filters will not work until
you add `filter.expression`.

## Getting application metrics into SigNoz

- **Traefik** (v3.5+ only): native OTLP export. In the Helm values set
  `metrics.otlp.enabled: true`, `metrics.otlp.http.endpoint`, and
  `metrics.otlp.resourceAttributes` to tag the cluster. On mocha it points at the
  in-cluster collector; on other clusters at the mTLS ingest endpoint with a client cert.
  Note: `metrics.otlp.resourceAttributes` did not exist before Traefik v3.5 and crashes the
  pod with `field not found`. With chart 41 / Traefik v3.7.5 the dotted key
  `resourceAttributes.k8s.cluster.name=<cluster>` IS emitted correctly (verified in SigNoz),
  so use `k8s.cluster.name` to match the built-in dashboards.
- **ArgoCD and other Prometheus-only apps**: add a `prometheus` receiver to the k8s-infra
  `otelDeployment.config` and a dedicated `metrics/<app>` pipeline, plus a `resource`
  processor to set `k8s.cluster.name`. On mocha the argocd metrics Services exist
  (`argocd-metrics:8082`, `argocd-server-metrics:8083`) so use `static_configs`. On turing
  those Services are absent, so use `kubernetes_sd_configs` (role pod, namespace argocd,
  relabel keep the port named `metrics`). Adding a new pipeline/receiver key deep-merges
  cleanly; do not rewrite existing pipelines.

## Showing friendly names for id-only metrics (PromQL info-metric join)

Some Prometheus exporters put the human name only on a separate `*_info` metric and label the
real metrics with an opaque id. `prometheus-pve-exporter` is the case in point: per-guest
metrics (`pve_cpu_usage_ratio`, `pve_memory_usage_bytes`, ...) carry only `id="qemu/123"`, while
the name lives on `pve_guest_info{id="qemu/123", name="traefik"}` (storage names on
`pve_storage_info`). To display the name, switch that panel's query from the builder to
**PromQL** and do an info-metric join:

```promql
pve_cpu_usage_ratio{id=~"qemu/.*"} * on (id) group_left(name) pve_guest_info
```

SigNoz's PromQL engine supports `group_left`, so this works (verified). Set the panel legend to
`{{name}}`. In the dashboard JSON the widget uses `query.queryType: "promql"` with
`query.promql[0] = {query, legend, name: "A", disabled: false}` and an empty
`builder.queryData`. Builder queries cannot do this join, so keep the id-based builder shape only
where the name does not matter (e.g. value/count panels).

## reduceTo must be "last", not "sum" (inflated value/pie/bar panels)

For value/pie/bar panels, each series is first reduced over the dashboard's time window by
`reduceTo`. With `reduceTo: "sum"` the panel adds up **every sample in the window**, so the
number is multiplied by the sample count (e.g. a 14.55 TiB pool showed ~55 TiB, "VMs running"
showed 81 instead of 9). Always use **`reduceTo: "last"`** to show the current value. Set it in
BOTH `queryData[].reduceTo` and each `queryData[].aggregations[].reduceTo`. This is the single
most common cause of "the metrics look summed / the number is way too big".

## The label `name` is ignored by the builder filter (use PromQL)

A builder `filter.expression` on the reserved key `name` is silently dropped: `name = 'x'`,
`name LIKE '...'` and `name != 'x'` all return every series unfiltered (verified against
`zfs_dataset_*`, whose dataset is labelled `name`). Filtering/excluding by `name` must be done
in **PromQL** (`queryType: "promql"`), where `name` is a normal label:
`zfs_dataset_used_bytes{type="filesystem",name=~".+/.+"}`. Note PromQL label matchers can't use
the dotted `k8s.cluster.name` easily, so drop that matcher when the metric only comes from one
source. `!=` and `LIKE` on other (non-reserved) keys via the builder are also unreliable; `=`
and `IN` and `LIKE` work on keys like `id`. When in doubt, verify with a `query_range` call.

## Don't sum metrics that overlap (ZFS datasets)

Some metrics represent a shared or nested resource and must never be summed across their series:
ZFS `zfs_dataset_available_bytes` is the pool's shared free space, reported identically on every
dataset (summing gave ~50 TiB on a 14.5 TiB pool) — show the pool value once
(`zfs_pool_free_bytes`) instead. ZFS `zfs_dataset_used_bytes` on the pool root dataset already
includes its children, so a per-dataset breakdown must exclude the root (`name=~".+/.+"`) or it
double-counts. Same idea for any parent/child or shared-resource metric.

## Dashboards as code

JSON files in `mocha/system/signoz/dashboards/`, bundled into a ConfigMap by
`configMapGenerator` in `kustomization.yaml` (needs `ServerSideApply=true` when the
ConfigMap exceeds 256 KB). A PostSync Job (`dashboard-provisioner.yaml`) imports them
through the API and **upserts** (PUT by id, fallback delete+POST), matched by title, so
editing a JSON and re-syncing updates the live dashboard. Community dashboards come from
`github.com/SigNoz/dashboards`.

## Alerting

- **Discord**: SigNoz has no native Discord channel. Discord accepts Slack-formatted
  payloads on the `/slack` suffix of a webhook URL, so create a Slack channel pointing at
  `<discord-webhook>/slack`. Store the webhook in Vault (`kv/discord#webhook`, `/slack`
  suffix included) and expose it via ExternalSecret. Provision the channel with
  `POST /api/v1/channels` (Alertmanager `slack_configs` shape). Test with
  `POST /api/v1/testChannel` (expects 204).
- **Alert rules**: `POST /api/v1/rules` (upsert PUT `/api/v1/rules/<id>`) requires the **v5
  schema**, otherwise it returns `version: only v5 is supported`. Shape: top-level
  `"version": "v5"`, and `condition.compositeQuery.queries: [{type: "builder_query", spec:
  {name, signal, disabled, aggregations: [{metricName, timeAggregation, spaceAggregation}],
  filter: {expression: "..."}, groupBy: [...]}}]`, plus `condition.op/target/matchType` and
  `selectedQueryName`. Set `preferredChannels: ["<channel name>"]`.
  - `groupBy` items in a v5 rule are `{"name": "<key>"}` ONLY. The dashboard groupBy shape
    (`dataType`/`id`/`key`/`type`) is rejected with `unknown field "dataType" in query spec`.
  - No-data alert (e.g. host down): add `condition.alertOnAbsent: true` and
    `condition.absentFor: <minutes>`.
  - The provisioner Job (`alerting.yaml`) upserts all rules by title on every sync; it holds
    the ArgoCD, ZFS-backup and Kubernetes alerts, all notifying the `discord` channel.
  - To get context (cluster, pod, app, pool) in the notification, the rule must `groupBy`
    those labels (they become alert labels) AND the channel template must print them. The
    Discord channel `text` uses `{{ range .Labels.SortedPairs }}• {{ .Name }}: {{ .Value }}`
    to list every label of the firing series.

## Applying changes

Everything is ArgoCD. `sys-signoz` (mocha) and `sys-signoz-k8s-infra` (turing) are the
parent apps generated by the ApplicationSets; they render the folder and update the child
`Application` objects, which then sync the Helm charts. To push a values change to a child
app, sync the parent first, then the child. The dashboard import Job and alerting Job are
PostSync hooks, re-run on every sync.

## ArgoCD Server-Side Apply diff bug (K8s 1.35)

Apps with `ServerSideApply=true` (traefik, signoz) got stuck with
`ComparisonError: ... .status.terminatingReplicas: field not declared in schema` on ArgoCD
v2.14 with K8s 1.35. `compare-options: ServerSideDiff=false` does NOT fix it. **Fixed by
upgrading ArgoCD to v3.0.5**; after the upgrade, hard-refresh the affected apps to clear the
cached error.

Upgrading ArgoCD without breaking AVP: ArgoCD is installed by Talos `extraManifests` from
`common/argocd/argocd.install.yaml`, which is the `kubectl kustomize` render of
`common/argocd/vault-argocd/` (base = `argo-cd//manifests/cluster-install?ref=<version>`
plus the repo-server patch that adds the three AVP CMP sidecars). To upgrade: bump the base
`ref`, set the AVP sidecar images in `vault-argocd/argocd-repo-server.yaml` to the SAME
version (the cmp-server protocol must match), regenerate `argocd.install.yaml`, commit, then
`kubectl apply --server-side --force-conflicts -f common/argocd/argocd.install.yaml`. The
`vault-credentials` secret (real Vault token) is created out of band and is preserved. Verify
AVP after: an app using `<path:kv/...>` (grafana, sys-signoz) must reach Synced.

Do not put comments in YAML manifests in this repo (repo owner preference).
