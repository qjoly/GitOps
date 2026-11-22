# netbird-proxy

Private Bring Your Own Proxy (BYOP) instance of the NetBird reverse proxy
([docs](https://docs.netbird.io/manage/reverse-proxy)), serving the apex
`px.mocha.thoughtless.eu`. Services created on that domain are NetBird-Only:
peers reach them over the WireGuard tunnel, TLS is terminated by the proxy with
the Cloudflare DNS-01 wildcard cert (`*.px.mocha.thoughtless.eu`, no public
inbound port needed), and no Traefik passthrough is required.

## Layout

- `manifests/proxy.yaml` — the `netbirdio/reverse-proxy` pod. It embeds a
  WireGuard peer, so it runs as root; netstack mode (`NB_USE_NETSTACK_MODE`)
  is required on k8s/Cilium (kernel WG in a pod netns never brings up its
  interface for the embedded client). `NB_PROXY_PRIVATE=true` advertises the
  Private capability that NetBird-Only services need.
- `manifests/certificate.yaml` — wildcard cert, hot-reloaded by the proxy from
  `/certs` (static cert mode, `NB_PROXY_ACME_CERTIFICATES=false`).
- `manifests/externalsecret.yaml` — the account-scoped proxy token
  (`kv/netbird` `proxy_token`, created via
  `POST /api/reverse-proxies/proxy-tokens`).

## NetBird-side state (not in git, set once via the API)

- DNS zone `px.mocha.thoughtless.eu` with distribution groups
  `users`, `americano`, and the mocha router group.
- A nameserver for that zone pointing at the router peer (`100.92.150.248`),
  groups `users`, `americano`, router group.
- Record `*.px.mocha.thoughtless.eu` A → the proxy peer's NetBird IP.

## Current routing (2026-11-22)

`*.px.mocha.thoughtless.eu` currently resolves to traefik-internal
(10.96.208.53), exactly like `*.nb`: the px zone's wildcard record points there
and apps publish a `*.px` Ingress of class `traefik-internal` with their own
`*.px` wildcard cert (see `../netbird-check`). The reverse proxy service above
stays configured but is NOT in the data path yet.

## Known caveats (0.83.x)

- The embedded peer has no persistent state (`state_path_set: false`), so a
  pod restart registers a NEW peer with a NEW NetBird IP: update the
  `*.px` DNS record afterwards (same caveat as the router, see
  `../system/netbird-operator`).
- The relay URL with a path (`rels://…:443/relay`) breaks the 0.83.2 QUIC
  dialer of the embedded client, so relay fallback is unavailable for it.
- The embedded proxy peer is not listed in `/api/peers` and cannot be added to
  a group, and the ACL policy that the docs say is auto-generated for
  NetBird-Only services does not appear: WG handshakes to the proxy peer
  succeed and its packets arrive, but it never answers (TCP times out), so
  inbound data is dropped inside the beta embedded client. Until that is
  fixed upstream, private services go through `*.nb` / `*.px` +
  traefik-internal instead (see "Current routing" above).

## Add a service

```bash
curl -sk -X POST -H "Authorization: Token $OPERATOR_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"name":"app.px.mocha.thoughtless.eu","domain":"app.px.mocha.thoughtless.eu","mode":"http","enabled":true,"pass_host_header":true,"private":true,"access_groups":["<users group id>"],"targets":[{"target_id":"<network resource id>","target_type":"host","host":"10.96.208.53","port":443,"protocol":"https","enabled":true,"options":{"skip_tls_verify":true}}]}' \
  https://netbird.mocha.thoughtless.eu/api/reverse-proxies/services
```

Target `10.96.208.53:443` is traefik-internal (publish the app there with an
Ingress of class `traefik-internal` for the `*.px` hostname, like
`netbird-check` does).
