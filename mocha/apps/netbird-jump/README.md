# netbird-jump

Reach NetBird-only services from a machine where the NetBird client can't be
installed: an unprivileged NetBird peer (netstack mode) runs in mocha and
exposes a SOCKS5 proxy, reached with `kubectl port-forward`.

```
Firefox + FoxyProxy ──SOCKS5──▶ kubectl port-forward ──▶ netbird-jump pod ──NetBird──▶ traefik-internal / peers
```

## Use it

Keep the port-forward running (it drops on idle and on pod restarts):

```bash
while true; do
  kubectl --context mocha-corium -n netbird-jump port-forward deploy/netbird-jump 1080:1080
  sleep 1
done
```

FoxyProxy (Firefox):

| Field | Value |
|---|---|
| Type | SOCKS5 |
| Host / Port | `127.0.0.1` / `1080` |
| Proxy DNS | **on** (names are resolved by the pod) |
| Pattern | `*.nb.mocha.thoughtless.eu` |

Check from a shell:

```bash
curl --socks5-hostname 127.0.0.1:1080 https://nginx-test.nb.mocha.thoughtless.eu/
```

## Add a service

Netstack mode has no NetBird DNS, so the pod resolves names through its
`/etc/hosts`. Add the hostname to `hostAliases` in `manifests/jump.yaml`
(no wildcard support), pointing at `10.96.208.53` for anything served by
traefik-internal, or at the peer's NetBird IP otherwise.

The peer joins the `users` NetBird group (setup key `k8s-netbird-jump`,
`kv/netbird` `jump_setup_key`), so it gets the same access as your devices.
