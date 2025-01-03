# Secret Management

To avoid storing secrets in the repository, we use Vault to store them (e.g., API keys, passwords, etc.). We then use the External Secrets operator to sync the secrets stored in Vault with the Kubernetes cluster.

## Vault

Vault is a tool for securely accessing secrets. A secret is anything that you want to tightly control access to, such as API keys, passwords, or certificates. Vault provides a unified interface to any secret while providing tight access control and recording a detailed audit log.

It is installed in the `vault` namespace using the ArgoCD application `vault` (see [here](https://github.com/qjoly/homelab/blob/3fc5c2fa7269afa87d6800083cbb2a0329e68cd8/lungo/system/vault.yaml) for an example).


### Initialize the Vault cluster

Everytime we restart the Vault cluster, we need to unseal it. The unseal process requires a quorum of the keys to be entered. In a normal condition, we would have multiple keys and multiple people to enter them. In our case, we have only one key and we will use it to unseal the cluster (maybe not the best practice, but it's a lab and I can't handle auto unseal for now).

```bash
kubectl exec -n vault vault-0 -- vault operator init \
    -key-shares=1 \
    -key-threshold=1 \
    -format=json > cluster-keys.json
```

You obtain the root token in the `cluster-keys.json` file. Ensure to keep it safe and **do not commit it to the repository** (or encrypt it if you do).

```bash
age -R ~/.ssh/id_ed25519.pub cluster-keys.json > cluster-keys.json.age # Encrypt the file
age -d -i ~/.ssh/id_ed25519 cluster-keys.json.age > cluster-keys.json # Decrypt the file
```

Now that our first Vault server is initialized, we need to unseal it and ask all the other Vault to join the cluster.

```bash
export VAULT_UNSEAL_KEY=$(jq -r ".unseal_keys_b64[]" cluster-keys.json)
kubectl exec -n vault -ti vault-0 -- vault operator unseal $VAULT_UNSEAL_KEY
kubectl exec -n vault -ti vault-1 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec -n vault -ti vault-1 -- vault operator unseal $VAULT_UNSEAL_KEY
kubectl exec -n vault -ti vault-2 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec -n vault -ti vault-2 -- vault operator unseal $VAULT_UNSEAL_KEY
```

If you restart the Vault cluster, you will need to unseal it again by running the same command.

### Enable the KV secret engine

Once the Vault cluster is ready, we can enable the KV secret engine kv (I will store the secrets in the `kv` path).

```bash 
kubectl port-forward -n vault svc/vault 8200:8200 
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN=$(jq -r ".root_token" cluster-keys.json)
vault secrets enable kv
vault login $(jq -r ".root_token" cluster-keys.json)
```

To test the Vault cluster, we can write a secret in the KV secret engine.

```bash
vault kv put kv/foo my-value=s3cr3t
```

## External Secrets

External Secrets allows you to use secrets stored in external secret management systems like AWS Secrets Manager, GCP Secret Manager, Azure Key Vault, and HashiCorp Vault. It is installed in the `external-secrets` namespace using the ArgoCD application `external-secrets` (see [here](https://github.com/qjoly/homelab/blob/3fc5c2fa7269afa87d6800083cbb2a0329e68cd8/lungo/system/external-secret.yaml) for an example).

*Note: This is actually the root token, which is not recommended for production use. In a production environment, you should create a dedicated token with the appropriate policies.*

***Create a secret with the Vault token***
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
stringData:
  token: $(jq -r ".root_token" cluster-keys.json)
metadata:
  name: vault-token
  namespace: external-secrets
type: Opaque
EOF
```

***Create a secret store that points to the Vault server***
```bash
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "http://vault.vault.svc.cluster.local:8200"
      path: "kv"
      version: "v1"
      auth:
        tokenSecretRef:
          name: "vault-token"
          key: "token"
          namespace: "external-secrets"
EOF
```

### Test the External Secrets

***Create an External Secret that syncs the secret in Vault with the Kubernetes cluster***
```bash
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: vault-example
  namespace: default
spec:
  refreshInterval: "15s"
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: example-sync # Name of the Secret in the target namespace
  data:
  - secretKey: foobar
    remoteRef:
      key: foo
      property: my-value
EOF
```

## ArgoCD Vault Plugin

For multiple applications, I use the ArgoCD Vault Plugin to sync the secrets stored in Vault with the Kubernetes cluster. The reason behind this is that some data I want to hide are not in secrets and ConfigMap (.e.g. I want to use a vault secret in an deployment annotation).


***Create a secret with the Vault token for the Vault Plugin***
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
stringData:
  AVP_AUTH_TYPE: token
  AVP_KV_VERSION: "1"
  AVP_TYPE: vault
  VAULT_ADDR: http://vault.vault.svc.cluster.local:8200
  VAULT_TOKEN: $(jq -r ".root_token" cluster-keys.json)
kind: Secret
metadata:
  name: vault-credentials
  namespace: argocd
type: Opaque
EOF
```

Now, we need to reinstall the ArgoCD but with the Vault Plugin enabled.

```bash
cd ./common/argocd/vault-argocd/
kubectl apply -k . -n argocd
```

Once everything is applied, we would be able to use the Vault Plugin in the ArgoCD application (e.g. here I want to hide the domain used by the ingress)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: glance
  namespace: argocd
spec:
  project: default
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
  destination:
    server: https://kubernetes.default.svc
    namespace: glance
  source:
    repoURL: https://rubxkube.github.io/charts/
    chart: glance
    targetRevision: 0.0.2
    plugin:
      name: argocd-vault-plugin-helm
      env:
        - name: HELM_VALUES
          value: |
            common:
              ingress:
                enabled: true
                hostName: "glance.<path:kv/cluster#domain>" # Just here ! 
                ingressClassName: nginx
```

