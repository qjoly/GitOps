---
name: signoz
description: Manage the self-hosted SigNoz observability stack in this GitOps repo. Use when creating or editing SigNoz dashboards, wiring application metrics into SigNoz (Traefik, ArgoCD, other Prometheus/OTLP sources), configuring alerting and notification channels (Discord), or debugging why a dashboard variable filter does not work. Covers the non-obvious formats SigNoz v0.14x expects.
---

# SigNoz on this cluster

SigNoz runs on the **mocha** cluster (`mocha/system/signoz/`), deployed by the `signoz`
Helm chart via ArgoCD. Other clusters ship telemetry to it over OTLP. Every source is
tagged with `k8s.cluster.name` so data can be told apart.

Kube contexts: `mocha-corium` (SigNoz host) and `omni-turing`. The SigNoz API key lives in
Vault at `kv/signoz#api_key`, exposed to the `signoz` namespace as the `signoz-api-key`
secret. Call the API with the header `SIGNOZ-API-KEY: <key>` against
`http://signoz.signoz.svc.cluster.local:8080`.

## The dashboard variable filter gotcha (most important)

SigNoz v0.14x applies query filters from the **`filter.expression`** field (a string),
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

## Cluster selector on a dashboard

To make a `k8s.cluster.name` selector that actually discriminates:

1. The metrics must carry the `k8s.cluster.name` resource attribute (see next section).
   Use `k8s.cluster.name`, the standard OTel key, not a custom `cluster` key: SigNoz's
   built-in dashboards use `k8s.cluster.name` and it behaves correctly.
2. Add a `ListVariable` backed by `signoz/DynamicVariable` (copy it from
   `mocha/system/signoz-resources/dashboards/traefik.yaml`):

```yaml
- kind: ListVariable
  spec:
    name: k8s.cluster.name
    allowAllValue: true
    allowMultiple: true
    sort: none
    plugin:
      kind: signoz/DynamicVariable
      spec:
        name: k8s.cluster.name
        signal: all
```

3. Add the filter to each query's `filter.expression`:
   `k8s.cluster.name IN $k8s.cluster.name`.

The simplest way to get a working dashboard is to copy the query/variable/filter shape
from a built-in k8s-infra dashboard (for example the "Kubernetes Node Metrics" one), which
uses the modern format: `aggregations: [{metricName, timeAggregation, spaceAggregation,
reduceTo, temporality}]` plus `filter.expression`. Old community dashboards use the legacy
`aggregateAttribute` + `filters.items` shape and their variable filters will not work until
you add `filter.expression`.

## Cluster selector pitfalls (shows 0 / wrong cluster)

A dynamic `k8s.cluster.name` variable with `signal: all` lists **every** cluster
(mocha, turing, doppio, proxmox-01, proxmox-02). Two failure modes:

- **Single-select (`allowMultiple: false`) on a metric that only exists on some clusters**: at load
  the selector lands on one value; if it's a cluster without that metric the whole dashboard shows
  0/blank (e.g. Rook mons = 0 because ceph only lives on turing). Fix by scope:
  - metric on ONE cluster (rook→turing, zfs→doppio): drop the variable, hardcode
    `k8s.cluster.name = '<cluster>'`.
  - metric on SEVERAL clusters (argocd, traefik on mocha+turing): set the variable to
    `allowMultiple: true` + `allowAllValue: true` so everything shows by default.
- **Literal `IN`/`LIKE` on `k8s.cluster.name` are silently ignored** by the builder filter (verified:
  `IN ('a','b')`, `IN ['a','b']`, `LIKE 'proxmox-%'` all return every cluster). Only `=` (one value)
  and `IN $variable` (multi-select var) actually filter. So to pin a panel to two specific clusters
  without a variable, use **two builder queries** (A: `= 'proxmox-01'`, B: `= 'proxmox-02'`), each
  `groupBy host.name` — not one `IN (...)` query. This is what the Proxmox host panels do, because
  `system.*` host metrics exist on every hostmetrics source (mocha/turing/doppio too), so an
  explicit per-cluster filter is mandatory.
- PromQL is NOT a workaround here: metrics with dotted names (`system.cpu.load_average.1m`) aren't
  addressable as `system_cpu_load_average_1m` in SigNoz PromQL (returns nothing).

## Getting application metrics into SigNoz

- **Traefik** (v3.5+ only): native OTLP export. In the Helm values set
  `metrics.otlp.enabled: true`, `metrics.otlp.http.endpoint`, and
  `metrics.otlp.resourceAttributes` to tag the cluster. On mocha it points at the
  in-cluster collector; on other clusters at the mTLS ingest endpoint with a client cert.
  Note: `metrics.otlp.resourceAttributes` did not exist before Traefik v3.5 and crashes the
  pod with `field not found`. With chart 41 / Traefik v3.7.5 the dotted key
  `resourceAttributes.k8s.cluster.name=<cluster>` IS emitted correctly (verified in SigNoz),
  so use `k8s.cluster.name` to match the built-in dashboards.
- **ArgoCD and other Prometheus-only apps**: add a `ServiceMonitor`/`PodMonitor`, picked up
  by `otel-metrics` on mocha and turing (see the ServiceMonitor section). The ArgoCD Helm chart
  does not create the `argocd-metrics` Service on mocha, so it is defined next to its
  ServiceMonitor in `mocha/system/servicemonitors/servicemonitors.yaml`. Fall back to a
  `prometheus` receiver in the k8s-infra `otelDeployment.config` (with its own `metrics/<app>`
  pipeline and a `resource` processor setting `k8s.cluster.name`) only where there is no
  ServiceMonitor path: doppio, or the existing plex/slimfaas static jobs on mocha.

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
`{{name}}`. In the Dashboard CR the query plugin is `signoz/PromQLQuery` with
`spec: {name: A, query, legend, disabled: false}` (see `dashboards/proxmox.yaml`). Builder queries cannot do this join, so keep the id-based builder shape only
where the name does not matter (e.g. value/count panels).

## reduceTo must be "last", not "sum" (inflated value/pie/bar panels)

For value/pie/bar panels, each series is first reduced over the dashboard's time window by
`reduceTo`. With `reduceTo: "sum"` the panel adds up **every sample in the window**, so the
number is multiplied by the sample count (e.g. a 14.55 TiB pool showed ~55 TiB, "VMs running"
showed 81 instead of 9). Always use **`reduceTo: "last"`** to show the current value, in each
entry of the query's `aggregations`. This is the single
most common cause of "the metrics look summed / the number is way too big".

## The label `name` is ignored by the builder filter (use PromQL)

A builder `filter.expression` on the reserved key `name` is silently dropped: `name = 'x'`,
`name LIKE '...'` and `name != 'x'` all return every series unfiltered (verified against
`zfs_dataset_*`, whose dataset is labelled `name`). Filtering/excluding by `name` must be done
in **PromQL** (`signoz/PromQLQuery`), where `name` is a normal label:
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

## ServiceMonitor / PodMonitor support (OTel Operator target allocator)

To scrape `ServiceMonitor`/`PodMonitor` CRs (Prometheus Operator style) without running
Prometheus, use the **OpenTelemetry Operator target allocator**. Two pieces, on mocha and turing
(doppio has neither):

- `*/system/otel-operator/` — the `opentelemetry-operator` Helm chart (needs cert-manager for
  its webhook). Set `manager.collectorImage` to the contrib image.
- `*/system/otel-metrics/` — an `OpenTelemetryCollector` (v1beta1, `mode: statefulset`) with
  `targetAllocator.enabled` + `targetAllocator.prometheusCR.enabled` and empty selectors
  (`serviceMonitorSelector: {}` / `podMonitorSelector: {}` = match all). Its prometheus
  receiver has empty `scrape_configs` and a `target_allocator` block pointing at the
  `<name>-targetallocator` service; the TA discovers the CRs and hands out targets. A
  `resource/cluster` processor stamps `k8s.cluster.name`.

RBAC is NOT created by the operator — ship two ClusterRoles+bindings (see `otel-metrics/rbac.yaml`):
the TA SA needs `monitoring.coreos.com` (servicemonitors/podmonitors/probes/scrapeconfigs) plus
namespaces/endpoints/services/pods/configmaps/secrets/endpointslices; the collector SA needs
nodes/nodes-metrics/services/endpoints/pods and more + `/metrics` nonResourceURL. The exact
lists are in `mocha/system/otel-metrics/rbac.yaml`. Set both via
`spec.serviceAccount` and `spec.targetAllocator.serviceAccount`. Put `POD_NAME` (fieldRef) in
`spec.env` and use it as `collector_id` so the TA can shard.

- **mocha**: collector in the `signoz` namespace, exporter `otlphttp` → `http://signoz-otel-collector.signoz.svc.cluster.local:4318`.
- **turing**: collector lives in the `signoz-k8s-infra` namespace to reuse the existing
  `signoz-mtls-ca` Issuer; a `Certificate` (`client auth`) is mounted at `/mtls` and the
  `otlphttp` exporter pushes to `https://signoz-ingest.mocha.thoughtless.eu` with
  `tls.cert_file`/`key_file`. No change to mocha's `signoz-mtls-ca` bundle is needed since the
  cert is signed by a CA already in it.

Gotchas: the collector may log one `dial tcp ... connect: operation not permitted` to the TA at
startup (Cilium identity not ready yet); it self-heals within ~30s (`Scrape job added`). The
contrib image has no shell, so debug from a separate curl pod, not `kubectl exec`. Verify in
ClickHouse by the metric names the target actually exposes (e.g. kubevirt's cdi target exposes
`controller_runtime_*`/`go_*`, not `cdi_*`). Add the `OpenTelemetryCollector` CR with
`argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true` so it doesn't fail before
the operator's CRD exists.

## Dashboards as code

Dashboards and alert rules are CRs reconciled by the SigNoz Operator, see the Operator
section below. Files live in `mocha/system/signoz-resources/dashboards/` and `rules/`.

## The v2 dashboard API (schema v6)

`POST /api/v1/dashboards` returns `501 dashboard_deprecated`. Probe the live API through
`/api/v2/dashboards`:

- List: `GET /api/v2/dashboards?limit=500` → `data.dashboards[]`, each has `id` and
  `spec.display.name`. **Match by `spec.display.name`** (the human title), NOT the top-level
  `name` — SigNoz appends a random suffix to `name` on create (`clickhouse-cold-storage` becomes
  `clickhouse-cold-storage-tazxbo0f`), so it is not a stable key.
- `PUT /api/v2/dashboards/{id}` returns 200 and keeps the id; `POST` returns 201;
  `DELETE /{id}` returns 204. `GET /api/v2/dashboards/{id}` is **501 Not Implemented** and the
  list truncates `spec` to `display` only — you cannot read a full dashboard back from the API.

### v6 dashboard JSON shape (what to write in the file)

```jsonc
{
  "schemaVersion": "v6",                 // required by POST/PUT
  "name": "clickhouse-cold-storage",     // required, RFC 1123 (lowercase, alnum, '-')
  "tags": [{"key": "tag", "value": "clickhouse"}],   // objects, not strings
  "spec": {                               // STRICT: rejects any unknown field
    "display": {"name": "ClickHouse Cold Storage", "description": "..."},
    "variables": [],
    "panels": {                           // dict keyed by panel id
      "put-rate": {
        "kind": "Panel",
        "spec": {
          "display": {"name": "PutObject / s", "description": ""},
          "plugin": {"kind": "signoz/NumberPanel",       // or signoz/TimeSeriesPanel
                     "spec": {"visualization": {"timePreference": "global_time"},
                              "formatting": {"unit": "reqps"},
                              "thresholds": []}},
          "queries": [{                    // EXACTLY ONE query per panel (see below)
            "kind": "scalar",              // "scalar" for NumberPanel, "time_series" for TimeSeriesPanel
            "spec": {"name": "A", "plugin": {"kind": "signoz/BuilderQuery", "spec": {
              "name": "A", "stepInterval": 60, "signal": "metrics",
              "aggregations": [{"metricName": "chi_clickhouse_event_S3PutObject",
                                "timeAggregation": "rate",
                                "spaceAggregation": "sum", "reduceTo": "last"}],
              "disabled": false, "filter": {"expression": "k8s.cluster.name = 'mocha'"},
              "groupBy": [], "having": {"expression": ""}, "legend": ""}}}}],
          "links": []
        }
      }
    },
    "layouts": [{"kind": "Grid", "spec": {"items": [
      {"x": 0, "y": 0, "width": 4, "height": 2, "content": {"$ref": "#/spec/panels/put-rate"}}
    ]}}],
    "links": []
  }
}
```

Hard rules learned by probing the API (error messages are precise, iterate against them):
- **One query per panel.** `queries` with >1 entry → `panel must have one query, found N`. To
  draw several series or a formula, use one `signoz/CompositeQuery` (see the Operator section).
- **Multi-series legends** collapse to metric-name auto-labels (one `legend` string per query). No
  per-series legend without a groupBy label.
- TimeSeriesPanel `plugin.spec` also needs `chartAppearance`, `axes`, and
  `legend: {position, mode}` (omit `customColors`); NumberPanel is lighter (`visualization`, `formatting`,
  `thresholds`).
- `spec` and each nested `spec` reject unknown fields (`json: unknown field "x"`). Do NOT carry
  over v1 keys (`widgets`, `layout`, `panelMap`, `uuid`, `version`, top-level `description`).

## Alerting## Alerting

- **Discord**: SigNoz has no native Discord channel. Discord accepts Slack-formatted
  payloads on the `/slack` suffix of a webhook URL, so create a Slack channel pointing at
  `<discord-webhook>/slack`. Store the webhook in Vault (`kv/discord#webhook`, `/slack`
  suffix included) and expose it via ExternalSecret. Provision the channel with
  `POST /api/v1/channels` (Alertmanager `slack_configs` shape). Test with
  `POST /api/v1/testChannel` (expects 204).
- **Alert rules**: `Rule` CRs (schema `v2alpha1`) in `mocha/system/signoz-resources/rules/`,
  all notifying the `discord` channel. Shape in the Operator section below.
  - No-data alert (e.g. host down): add `condition.alertOnAbsent: true` and
    `condition.absentFor: <minutes>`.
  - To get context (cluster, pod, app, pool) in the notification, the rule must `groupBy`
    those labels (they become alert labels) AND the channel template must print them. The
    Discord template in `signoz-resources/discord-channel.yaml` prints every label as
    `name=value`, skips `alertname`/`severity`/`ruleId`/`ruleSource`, and stops at 10 alerts to
    stay under Discord's 4096-character limit.

## SigNoz Operator: dashboards and alerts are CRs

`mocha/system/signoz-operator/` (chart `signoz-operator`, needs `ServerSideApply=true`:
the `dashboards` CRD is 95 KB) + `mocha/system/signoz-resources/` (a `ProviderConfig`,
the `Dashboard` and `Rule` CRs, and the Discord-channel Job — there is no `Channel` kind).
Use the **typed** `objectTemplate.spec`, not `jsonSpec`: the API server then validates
the whole body at apply time.

Validate any change **twice**, they catch different things:

1. against the CRD schema offline — `helm template signoz/signoz-operator --include-crds`,
   then jsonschema the CRs against `openAPIV3Schema`;
2. against the **live API**, by POSTing `objectTemplate.spec` to
   `/api/v2/dashboards` or `/api/v1/rules` and DELETEing what got created.

The CRD models one permissive union for every panel kind, so step 1 passes shapes the
live API refuses. Per-kind accepted `plugin.spec` keys (probed on 0.143):

| kind | keys |
|---|---|
| TimeSeriesPanel | visualization(+fillSpans), formatting, chartAppearance, axes, legend, thresholds |
| BarChartPanel | visualization(+fillSpans), formatting, axes, legend, thresholds — NO chartAppearance |
| NumberPanel | visualization, formatting, thresholds |
| TablePanel | visualization, formatting (NO `unit`), thresholds |
| PieChartPanel | visualization, formatting, legend |
| HistogramPanel | legend only. ListPanel: nothing |

Other live-only rules: `allowAllValue` requires `allowMultiple: true` on a variable;
`signoz/PromQLQuery` is only accepted on TimeSeries/Number/BarChart panels (use a bar
chart instead of a PromQL table or pie); `signoz/ClickHouseSQL` works everywhere.
Omit `decimalPrecision` (the CRD enum mixes ints and `full`, nothing validates), omit
`temporality: ""` / `source: ""`, and use `thresholds: []` rather than `null`.

**One query per panel still holds**, but `signoz/CompositeQuery` is the way around it:
its `spec.queries` holds several `{type: builder_query}` sub-queries plus
`{type: builder_formula, spec: {expression: "A/B"}}`. That is how a v1 panel with
queries A/B and a formula converts without loss.

Rules use schema **v2alpha1**: `evaluation: {kind: rolling, spec: {evalWindow, frequency}}`,
`condition.thresholds: {kind: basic, spec: [{name, op, matchType, target, channels}]}`
(`channels` replaces `preferredChannels`), `notificationSettings` required
(`usePolicy: false`), `groupBy` items are `{name: <key>}`, `alertOnAbsent`/`absentFor`
unchanged.

The API key must belong to a SigNoz **service account with a role attached** — a
role-less token authenticates fine and then 403s on everything
(`service_account/<uuid> is not authorized to perform dashboard:list`). Grant Admin in
the UI; the operator cannot bootstrap its own role.

Cluster context is **`mocha-corium`** (the `omni-*` contexts need an interactive browser
login and fail headless).

## Applying changes

Everything is ArgoCD. On mocha the parent apps are `sys-signoz`, `sys-signoz-operator`,
`sys-signoz-resources`, `sys-otel-metrics`, `sys-otel-operator`, `sys-obi` and
`sys-servicemonitors`; turing and doppio have `sys-signoz-k8s-infra`. A parent renders the
folder and updates the child `Application`, which then syncs the chart: sync the parent first,
then the child. The operator reconciles Dashboards and Rules continuously; the only PostSync
hook left is the `signoz-discord-channel` Job.

## ArgoCD Server-Side Apply diff bug (K8s 1.35, turing)

Apps with `ServerSideApply=true` (traefik, signoz) got stuck with
`ComparisonError: ... .status.terminatingReplicas: field not declared in schema` on ArgoCD
v2.14 with K8s 1.35. `compare-options: ServerSideDiff=false` does NOT fix it. **Fixed by
upgrading ArgoCD to v3.0.5**; after the upgrade, hard-refresh the affected apps to clear the
cached error.

On mocha and doppio (Corium), ArgoCD is a k0s Helm add-on declared in
`<cluster>/corium/<cluster>.yaml`: bump its `version` there and `cctl apply`.

### Upgrading ArgoCD on turing (vanilla)

turing runs **vanilla** ArgoCD and was stuck on v2.14.21,
hitting the same `.status.terminatingReplicas` ComparisonError (apps stuck `Unknown`). It is
installed via Talos `extraManifests` pointing at `common/argocd/argocd.install.vanilla.yaml`
(a plain `kubectl kustomize "argo-cd//manifests/cluster-install?ref=v3.0.5"` render) plus
`argocd.config.yaml`. Two gotchas when applying the upgrade live:
- The upstream `cluster-install` manifest has **no `namespace:` on resources** — you MUST
  `kubectl apply -n argocd`, otherwise everything lands in `default` (delete the stray
  `-l app.kubernetes.io/part-of=argocd` objects from `default` if that happens).
- The control-plane Deployments/StatefulSet have an **immutable `spec.selector`** that differs
  between v2.14 and v3.0.5, so `apply` fails with "field is immutable". You must
  `kubectl -n argocd delete deploy/statefulset` for the 6 workloads, then re-apply (recreates
  them at v3.0.5). ArgoCD is down ~1-2 min; deployed apps are unaffected. `argocd-secret` is
  preserved (empty `data` in the manifest = server-side apply takes no ownership). Re-apply
  `argocd.config.yaml` after to restore admin.enabled/resource.exclusions.

Do not put comments in YAML manifests in this repo (repo owner preference).
