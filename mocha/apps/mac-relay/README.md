# mac-relay

Publish a port of the Mac as a **definitive URL on NetBird**:
`https://mac.nb.mocha.thoughtless.eu/` reaches whatever the Mac exposes locally,
for every NetBird peer — without installing the NetBird client on the Mac and
without depending on its (unstable) NetBird IP.

```
NetBird peer ──https──▶ traefik-internal ──▶ mac-relay :8080 ──chisel reverse──┐
                                                                                ▼
Mac: mise run nb:mac ──chisel client──▶ kubectl port-forward ──▶ mac-relay :2333 ──▶ 127.0.0.1:<NB_MAC_PORT>
```

The `*.nb.mocha.thoughtless.eu` wildcard already resolves to traefik-internal
everywhere (NetBird zone CNAME for peers, CoreDNS sidecar in netbird-jump for
pods, `/etc/resolver` + pf on the Mac), and traefik-internal serves the `*.nb`
wildcard cert — so `mac.nb.mocha.thoughtless.eu` needs **no DNS record**.

## Prerequisites

- The `mac_relay_auth` secret in Vault, shared between the pod and the Mac:

  ```bash
  mise run vault:kv patch kv/netbird mac_relay_auth="mac:$(openssl rand -hex 24)"
  ```

- `kubectl` with the kubelogin plugin and the authentik `Admins` group
  (port-forward), same as [`netbird-jump`](../netbird-jump/README.md).
- `chisel` on the Mac: installed by `mise install` (see `mise.toml`).

## Use it

From the repo, on the Mac:

```bash
export NB_MAC_RELAY_AUTH="$(mise run vault:kv get kv/netbird mac_relay_auth -o jsonpath 2>/dev/null || true)"
# simpler: paste the value once, or read it with vault directly
export NB_MAC_RELAY_AUTH='mac:…'
NB_MAC_PORT=3000 mise run nb:mac    # Ctrl-C to stop
```

`nb:mac` keeps a `kubectl -n mac-relay port-forward deploy/mac-relay 2333:2333`
open and runs `chisel client … 127.0.0.1:2333 R:8080:127.0.0.1:$NB_MAC_PORT` in a
loop (the port-forward drops on idle and on pod restarts). The relay pod then
listens on `:8080` and forwards to the Mac.

From any NetBird peer (or from the Mac itself via `nb:setup` + `nb:tunnel`):

```bash
curl https://mac.nb.mocha.thoughtless.eu/
```

## Notes

- While no Mac is connected, nothing listens on `:8080` and traefik answers
  **502** — that is the "Mac offline" signal, not a misconfiguration.
- The control port 2333 is **not** exposed through traefik-internal
  (see `networkpolicy.yaml`); only `kubectl port-forward` reaches it, and it
  requires `--auth`.
- Only one Mac at a time: the pod has a single replica (`Recreate`), so a second
  `nb:mac` client fails to bind `:8080`.
- To expose something else than the Mac (a cluster Service), use the plain
  `traefik-internal` Ingress pattern of [`netbird-check`](../netbird-check) —
  no relay needed.
