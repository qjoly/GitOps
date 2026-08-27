# abcdesktop

[abcdesktop.io](https://www.abcdesktop.io/) 4.4, the GitOps way: the upstream
`install-4.4.sh` script is not run, its two downloads are vendored in
`manifests/` and everything the script would have generated locally (RSA keys,
mongodb keyfile) comes from Vault instead.

Reachable on <https://abcdesktop.mocha.thoughtless.eu>, behind authentik.

## Local changes to the upstream files

- `od.config`: `default_host_url` points to the ingress and `websocketrouting`
  uses it instead of the `Origin` header.
- `od.config`: the `authmanagers` block declares authentik as the only provider
  and disables the LDAP demo directory and the anonymous login that ship with
  abcdesktop. The matching authentik provider lives in
  `mocha/system/authentik/authentik.yaml`, provisioned like the others. It is a
  public OAuth2 client: pyos reads its config from a ConfigMap, which is not a
  place for a client secret. The `openldap-od` deployment is left running, it
  simply has no user anymore.
- `od.config`: the desktop home directory is a per-user PVC instead of an
  emptyDir, so a session survives a pod restart.
- `manifests/kustomization.yaml`: drops the upstream `secret-mongodb`, whose
  passwords are public, and moves the mongodb data to a PVC.

If the upstream `mongodb-init-replica` Job ever changes, the sync will fail on
its immutable spec: delete the Job and let ArgoCD recreate it. Do not reach for
`Replace=true`, ArgoCD then replaces the Job on *every* sync and a live Job has
no `spec.selector` to replace with.

Everything else is upstream, so refreshing the app means re-downloading the two
files:

```bash
cd mocha/apps/abcdesktop/manifests
curl -sLO https://raw.githubusercontent.com/abcdesktopio/conf/main/kubernetes/abcdesktop-4.4.yaml
curl -sL https://raw.githubusercontent.com/abcdesktopio/conf/main/reference/od.config.4.4 -o od.config
# then reapply the od.config edits listed above
```

## One-shot: push the secrets to Vault

The ExternalSecrets read a single `kv/abcdesktop` entry. Generate it once
(see [secret management](../../../docs/secret-management.md) for the port-forward
and the token):

```bash
cd "$(mktemp -d)"
for k in desktop_payload desktop_signing user_signing; do
  openssl genrsa -out "$k.key" 2048
  openssl rsa -in "$k.key" -outform PEM -pubout -out "$k.pub"
done
# the payload public key uses the RSAPublicKey form, unlike the two others
openssl rsa -pubin -in desktop_payload.pub -RSAPublicKey_out -out desktop_payload.pub

vault kv put kv/abcdesktop \
  jwt_desktop_payload_private_key=@desktop_payload.key \
  jwt_desktop_payload_public_key=@desktop_payload.pub \
  jwt_desktop_signing_private_key=@desktop_signing.key \
  jwt_desktop_signing_public_key=@desktop_signing.pub \
  jwt_user_signing_private_key=@user_signing.key \
  jwt_user_signing_public_key=@user_signing.pub \
  mongod_keyfile="$(openssl rand -base64 756 | tr -d '\n')" \
  mongo_root_password="$(openssl rand -hex 16)" \
  mongo_pyos_password="$(openssl rand -hex 16)"
```

## Applications

Applications are not part of the desktop image: each one runs as its own
container inside the session pod. They live in mongodb, and upstream registers
them by POSTing a `docker inspect` output to the pyos manager API — there is no
manifest for it. `manifests/apps-register.yaml` does that from a list of image
references, rebuilding the payload from the registry API (no docker daemon
involved), as an ArgoCD PostSync hook. To add an application, add its image to
the `applist` key and sync.

Available images are the `*.d` ones in `ghcr.io/abcdesktopio`, built from
[oc.apps](https://github.com/abcdesktopio/oc.apps).

Currently registered: Firefox (Ubuntu and Rocky Linux builds), VSCode and a
Terminal. `vscode.d` already carries git, gcc, make, golang and pre-commit;
`terminal.d` carries git, ssh and sshfs.

`mise` has no distribution package, so the session init container drops its
static binary into `~/.local/bin` and puts `~/.local/share/mise/shims` on the
PATH through `.bashrc`. Both live in the home PVC, so it survives sessions and
is visible from every application container. Pin its version in `od.config` when
upgrading.

The desktop image itself is Ubuntu-only upstream: `oc.user` ships a
`Dockerfile.ubuntu` and nothing else, so there is no Fedora session image. The
RPM-based application images (`firefoxrockylinux.d`, `firefoxalmalinux.d`) are
the closest thing available, and they run fine next to the Ubuntu desktop.

## Single session only

Sized for one desktop at a time: everything runs with `replicas: 1`. State is
persistent though — mongodb keeps its data in `mongodb-data`, and each user gets
a 10Gi home PVC named `authentik-<userid>`, kept when the session ends
(`desktop.removepersistentvolumeclaim` stays False).

Desktop images are pulled on demand from `ghcr.io/abcdesktopio`, the first login
takes a while.
