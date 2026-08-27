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
  passwords are public, makes the mongodb init Job replaceable, and moves the
  mongodb data to a PVC.

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

## Single session only

Sized for one desktop at a time: everything runs with `replicas: 1`. State is
persistent though — mongodb keeps its data in `mongodb-data`, and each user gets
a 10Gi home PVC named `authentik-<userid>`, kept when the session ends
(`desktop.removepersistentvolumeclaim` stays False).

Desktop images are pulled on demand from `ghcr.io/abcdesktopio`, the first login
takes a while.
