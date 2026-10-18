#!/usr/bin/env python3
"""Render the SigNoz ingress inventory into Homepage's services.yaml.

The inventory is collected by the k8sobjects receiver on every cluster, so this
reads one source and gets every cluster at once. Only the Python standard
library is used, which keeps the job image a plain python:alpine.
"""

import json
import os
import ssl
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

CLICKHOUSE_URL = os.environ["CLICKHOUSE_URL"]
WINDOW_MINUTES = int(os.environ.get("WINDOW_MINUTES", "30"))
NAMESPACE = os.environ["NAMESPACE"]
CONFIGMAP = os.environ["CONFIGMAP"]
DEPLOYMENT = os.environ["DEPLOYMENT"]
ICON_INDEX = os.environ.get("ICON_INDEX", "")

SA_DIR = "/var/run/secrets/kubernetes.io/serviceaccount"
API = "https://kubernetes.default.svc"

# Each poll re-emits the whole inventory, so restricting the rows to the most
# recent batch per cluster is what makes a deleted Ingress disappear.
QUERY = f"""
WITH latest AS (
    SELECT
        resources_string['k8s.cluster.name'] AS cluster,
        max(timestamp) AS last_seen
    FROM signoz_logs.distributed_logs_v2
    WHERE timestamp > toUnixTimestamp64Nano(now64() - INTERVAL {WINDOW_MINUTES} MINUTE)
      AND mapContains(attributes_string, 'ingress.url')
    GROUP BY cluster
)
SELECT DISTINCT
    resources_string['k8s.cluster.name'] AS cluster,
    attributes_string['ingress.namespace'] AS namespace,
    attributes_string['ingress.name'] AS name,
    attributes_string['ingress.url'] AS url
FROM signoz_logs.distributed_logs_v2
INNER JOIN latest ON latest.cluster = resources_string['k8s.cluster.name']
WHERE timestamp > toUnixTimestamp64Nano(now64() - INTERVAL {WINDOW_MINUTES} MINUTE)
  AND mapContains(attributes_string, 'ingress.url')
  AND timestamp >= latest.last_seen - 60000000000
ORDER BY cluster, namespace, name
FORMAT JSONEachRow
"""


def query_clickhouse():
    request = urllib.request.Request(CLICKHOUSE_URL, data=QUERY.encode())
    with urllib.request.urlopen(request, timeout=30) as response:
        body = response.read().decode()
    return [json.loads(line) for line in body.splitlines() if line.strip()]


def load_icons():
    """Names known to dashboard-icons, keyed both as-is and without dashes."""
    if not ICON_INDEX:
        return {}
    try:
        with urllib.request.urlopen(ICON_INDEX, timeout=20) as response:
            names = json.load(response)["svg"]
    except Exception as error:
        print(f"icon index unavailable, rendering without icons: {error}")
        return {}
    index = {}
    for filename in names:
        stem = filename.rsplit(".", 1)[0]
        index.setdefault(stem, stem)
        index.setdefault(stem.replace("-", ""), stem)
    return index


def resolve_icon(name, index):
    """Match argocd -> argo-cd, atuin-web -> atuin, and give up quietly."""
    parts = name.split("-")
    for cut in range(len(parts), 0, -1):
        candidate = "-".join(parts[:cut])
        for key in (candidate, candidate.replace("-", "")):
            if key in index:
                return index[key]
    return None


def render(rows, index):
    clusters = {}
    for row in rows:
        clusters.setdefault(row["cluster"], []).append(row)
    lines = ["# Generated from the SigNoz ingress inventory. Do not edit by hand."]
    for cluster in sorted(clusters):
        lines.append(f"- {json.dumps(cluster)}:")
        for row in sorted(clusters[cluster], key=lambda r: (r["namespace"], r["name"])):
            icon = resolve_icon(row["name"], index)
            lines.append(f"    - {json.dumps(row['name'])}:")
            lines.append(f"        href: {json.dumps(row['url'])}")
            lines.append(f"        description: {json.dumps(row['namespace'])}")
            if icon:
                lines.append(f"        icon: {json.dumps(icon + '.svg')}")
    return "\n".join(lines) + "\n"


def kube(method, path, body=None, content_type="application/strategic-merge-patch+json"):
    with open(f"{SA_DIR}/token") as handle:
        token = handle.read()
    request = urllib.request.Request(
        API + path,
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
    )
    request.add_header("Authorization", f"Bearer {token}")
    if body is not None:
        request.add_header("Content-Type", content_type)
    context = ssl.create_default_context(cafile=f"{SA_DIR}/ca.crt")
    with urllib.request.urlopen(request, context=context, timeout=30) as response:
        return json.loads(response.read().decode())


def main():
    rows = query_clickhouse()
    if not rows:
        sys.exit("no ingress rows returned, refusing to publish an empty dashboard")

    content = render(rows, load_icons())
    path = f"/api/v1/namespaces/{NAMESPACE}/configmaps/{CONFIGMAP}"

    try:
        current = kube("GET", path)
        exists = True
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        current, exists = {}, False

    if exists and current.get("data", {}).get("services.yaml") == content:
        print(f"{len(rows)} ingresses, unchanged")
        return

    if exists:
        kube("PATCH", path, {"data": {"services.yaml": content}})
    else:
        kube(
            "POST",
            f"/api/v1/namespaces/{NAMESPACE}/configmaps",
            {
                "apiVersion": "v1",
                "kind": "ConfigMap",
                "metadata": {"name": CONFIGMAP, "namespace": NAMESPACE},
                "data": {"services.yaml": content},
            },
            content_type="application/json",
        )

    # services.yaml is mounted with subPath, which never refreshes in place.
    kube(
        "PATCH",
        f"/apis/apps/v1/namespaces/{NAMESPACE}/deployments/{DEPLOYMENT}",
        {
            "spec": {
                "template": {
                    "metadata": {
                        "annotations": {
                            "homepage.thoughtless.eu/restarted-at": datetime.now(
                                timezone.utc
                            ).isoformat()
                        }
                    }
                }
            }
        },
    )
    print(f"{len(rows)} ingresses published, homepage restarted")


if __name__ == "__main__":
    main()
