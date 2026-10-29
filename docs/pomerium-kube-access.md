# Reaching a Kubernetes API server through Pomerium

Runbook for the `kube-lab` guest cluster on `mocha`, whose API server is not
exposed directly: Pomerium fronts it, authenticates the user against Dex (which
federates to authentik), then impersonates that user on the API server.

```
kubectl --> Pomerium --> Dex --> authentik
               |
               +-- impersonation --> kube-lab API server
```

The API server itself has no OIDC flags. Pomerium holds a ServiceAccount with
the `impersonate` verb and sets `Impersonate-User` once the IdP has vouched for
the caller, so RBAC applies to the human identity, not to the ServiceAccount.

## Install the CLI

`pomerium-cli` is the kubectl credential plugin. It is in neither the mise nor
the aqua registry, so mise installs it straight from the GitHub release. The
archive ships the binary as `pomerium-cli` rather than `cli` (the repo name),
which is why the `exe` option is needed — without it the install fails with
`could not find any files matching [cli*]`.

It is already pinned in [`mise.toml`](../mise.toml):

```toml
[tools]
"github:pomerium/cli" = { version = "0.33.1", exe = "pomerium-cli" }
```

```bash
mise install
```

Use the `github:` backend, not `ubi:` — the latter is deprecated and disappears
in mise 2027.1.0. The install verifies GitHub artifact attestations and SLSA
provenance.

## Get the kubeconfig

```bash
mise run kube-lab:kubeconfig
```

Writes `~/kubeconfig.kube-lab`. The file holds no credentials and no CA data:
Pomerium serves a publicly trusted certificate, and the token is fetched per
call by the exec plugin.

Override with `POMERIUM_KUBE_ROUTE` (default
`https://kube-lab.mocha.thoughtless.eu`) or `KUBE_LAB_KUBECONFIG`.

The task writes the YAML by hand instead of using `kubectl config
set-credentials`, which rewrites an absolute exec command into a path relative
to the kubeconfig — that only resolves when kubectl happens to run from that
directory.

## Use it

```bash
export KUBECONFIG=~/kubeconfig.kube-lab
kubectl get namespaces
```

The first call opens a browser for the Dex then authentik login. The token is
cached in the system keychain afterwards.

`kubectl get nodes` returns an empty list. That is expected: the guest runs
`k3s server --disable-agent`, so there is a control plane and no kubelet.

## Web UI

Pomerium Core serves a user dashboard on any protected route:

| URL | Shows |
| --- | --- |
| `https://kube-lab.mocha.thoughtless.eu/.pomerium/` | current session, IdP claims, groups |
| `.../.pomerium/webauthn` | enroll and manage hardware keys |
| `.../.pomerium/jwt` | the identity JWT passed upstream |
| `.../.pomerium/sign_out` | sign out |

It is a user-facing page, not an admin console: routes and policies are
configured only through YAML or CRDs. The admin console is a separate
commercial product.

## Troubleshooting

**A login loop, or a stale identity.** Clear the cached credential:

```bash
pomerium-cli k8s flush-credentials https://kube-lab.mocha.thoughtless.eu
```

**`500 Internal Server Error` on `/oauth2/callback` right after a successful
login.** The code exchange between Pomerium and Dex failed. Check Dex:

```bash
kubectl -n pomerium-lab logs deploy/dex | grep -i "client_secret\|login successful"
```

`invalid client_secret on token request` means Pomerium's `IDP_CLIENT_SECRET`
and Dex's static client disagree. Note that Dex expands `$VARS` in *connector*
config but not in `staticClients`, where the field is `secretEnv`:

```yaml
staticClients:
  - id: pomerium
    secretEnv: POMERIUM_CLIENT_SECRET   # not: secret: $POMERIUM_CLIENT_SECRET
```

**`invalid_request` / "The request is otherwise malformed" from authentik.**
OAuth2 providers created through the authentik API get `grant_types: []`, and
nothing fills a default. The provider needs
`["authorization_code", "refresh_token"]`. Providers created from a blueprint
already have it.

**Everything 403s after a Dex restart.** Dex runs with `storage: memory` here,
so it regenerates its signing keys on every restart and invalidates every token
it ever issued. Sign in again. A persistent backend is required for anything
beyond a lab.

**`exec plugin is configured to use API version client.authentication.k8s.io/v1beta1,
plugin returned version client.authentication.k8s.io/v1`.** The browser login
succeeds and kubectl then rejects the credential it just received.
`pomerium-cli` only ever emits `v1`, so the kubeconfig must declare `v1`, not
`v1beta1`. Regenerate it with `mise run kube-lab:kubeconfig`.

**`interactiveMode must be specified for kube-lab to use exec authentication
plugin`.** `interactiveMode` is optional in `v1beta1` but required in `v1`.
`IfAvailable` is the right value here: the first call opens a browser, later
ones reuse the cached token without needing a terminal.

**`kubectl exec` or `port-forward` hangs.** Those ride upgraded streams; the
route needs `allow_spdy: true` and `allow_websockets: true`.
