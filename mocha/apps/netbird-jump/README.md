# netbird-jump

Reach NetBird-only services (`*.nb.mocha.thoughtless.eu`) from a machine where
the NetBird client can't be installed: an unprivileged NetBird peer (netstack
mode) runs in mocha and exposes a SOCKS5 proxy, reached with
`kubectl port-forward`.

```
Firefox + FoxyProxy ──SOCKS5──▶ kubectl port-forward ──▶ netbird-jump pod ──NetBird──▶ traefik-internal / peers
```

## Prerequisites

- `kubectl` with the [kubelogin](https://github.com/int128/kubelogin) plugin
  (`kubectl oidc-login`).
- [`mocha/kubeconfig`](../../kubeconfig): logs in through authentik. Port-forward
  needs the authentik `Admins` group, the only one bound in mocha.
- Outbound access to `5.196.80.72:6443`.

## Use it

1. Open the tunnel and keep it running. It drops on idle and when the pod
   restarts, hence the loop:

   ```bash
   export KUBECONFIG=mocha/kubeconfig
   while true; do
     kubectl -n netbird-jump port-forward deploy/netbird-jump 1080:1080
     sleep 1
   done
   ```

2. In FoxyProxy (Firefox), add a proxy:

   | Field | Value |
   |---|---|
   | Type | SOCKS5 |
   | Hostname / Port | `127.0.0.1` / `1080` |
   | Proxy DNS | **on**: the pod resolves the names |

   Add an include pattern to it: type Wildcard, `*.nb.mocha.thoughtless.eu`.
   Then switch FoxyProxy to "Proxy by Patterns", so only those hosts use the
   tunnel.

3. Browse `https://nginx-test.nb.mocha.thoughtless.eu/`, or check from a shell:

   ```bash
   curl --socks5-hostname 127.0.0.1:1080 https://nginx-test.nb.mocha.thoughtless.eu/
   ```

## Troubleshooting

| Symptom | Cause |
|---|---|
| Connection refused on 127.0.0.1:1080 | The port-forward is down: see step 1 |
| Timeout or 404 | Proxy DNS is off, or the hostname is missing from `hostAliases`: the public wildcard `*.mocha.thoughtless.eu` answers instead |
| Timeout on a hostname listed in `hostAliases` | The NetBird path: check the router conntrack in `netbird-operator`. The ClusterIP only answers forwarded traffic because Cilium has `socketLB.hostNamespaceOnly` (`mocha/corium/mocha.yaml`) |

## Add a service

Netstack mode has no NetBird DNS, so the pod resolves names through its
`/etc/hosts`. Add the hostname to `hostAliases` in `manifests/jump.yaml`
(no wildcard support), pointing at `10.96.208.53` for anything served by
traefik-internal, or at the peer's NetBird IP otherwise.

The peer joins the `users` NetBird group (setup key `k8s-netbird-jump`,
`kv/netbird` `jump_setup_key`), so it gets the same access as your devices.
