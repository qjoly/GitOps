# ristretto

Single-node Talos cluster on `homelab-proxmox-01` (VM 160), reachable at
`192.168.0.188`. It is NOT driven by ArgoCD: the machine config patches and the
agent values here are versioned for traceability and applied by hand.

## Talos

`talos/patches/` holds the config patches fed to `talosctl gen config`. The
secrets (`secrets.yaml`, `talosconfig`) live in `~/.talos/ristretto` and are
never committed; the copy of record is OpenBao on mocha, under
`kv/talos-ristretto`. Losing both means losing control of the cluster.

```sh
mkdir -p ~/.talos/ristretto
export VAULT_CONTEXT=mocha-corium
mise run vault:kv get -field=secrets.yaml kv/talos-ristretto > ~/.talos/ristretto/secrets.yaml
mise run vault:kv get -field=talosconfig kv/talos-ristretto > ~/.talos/ristretto/talosconfig
chmod 600 ~/.talos/ristretto/secrets.yaml
```

```sh
talosctl gen config ristretto https://192.168.0.188:6443 \
  --with-secrets ~/.talos/ristretto/secrets.yaml \
  --config-patch @talos/patches/node.yaml \
  --config-patch @talos/patches/hostname.yaml \
  --config-patch @talos/patches/oidc.yaml \
  --config-patch @talos/patches/workload-on-cp.yaml \
  --output-dir ~/.talos/ristretto --force
```

Two Talos 1.13 gotchas are baked into the patches: the hostname moved out of
the `v1alpha1` document into `HostnameConfig`, and that document refuses a
static `hostname` next to its generated `auto: stable`.

## Authentication

The apiserver trusts the `ristretto-oidc` client of mocha's authentik (see
`mocha/system/authentik/authentik.yaml`). The username claim is `sub`, not
`email`: authentik sends `email_verified: false` and Kubernetes then refuses an
email username.

## RBAC

`rbac/cluster-admin.yaml` binds the OIDC identity to `cluster-admin`. The
apiserver runs with `oidc-username-claim: sub` and `oidc-username-prefix: "-"`,
so the username is the `sub` verbatim — an email, not a prefixed issuer path.

```sh
kubectl apply -f rbac/cluster-admin.yaml
```

## ProxyAuthK8S

The cluster sits behind the home NAT, so mocha cannot reach its apiserver. The
agent below dials out to mocha's agent gateway instead
(`agent-proxyauth.mocha.thoughtless.eu`), and the matching `ProxyKubeApi` lives
in `mocha/apps/proxyauthk8s/manifests/ristretto.yaml`.

```sh
helm upgrade --install agent oci://ghcr.io/batleforc/proxyauthk8s/chart-agent \
  --version 0.4.0 -n proxyauth-agent --create-namespace \
  -f proxyauth-agent/values.yaml
```

The release name matters: it fixes the ServiceAccount name
(`agent-proxyauthk8s-agent`), which the `ProxyKubeApi` names as its `subject`.
