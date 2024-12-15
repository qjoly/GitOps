## Secret Management

To avoid storing secrets in the repository, we use Vault to store them (e.g., API keys, passwords, etc.). We then use the External Secrets operator to sync the secrets stored in Vault with the Kubernetes cluster.

### Vault

Vault is a tool for securely accessing secrets. A secret is anything that you want to tightly control access to, such as API keys, passwords, or certificates. Vault provides a unified interface to any secret while providing tight access control and recording a detailed audit log.

It is installed in the `vault` namespace using the ArgoCD application `vault` (see [here](https://github.com/qjoly/homelab/blob/3fc5c2fa7269afa87d6800083cbb2a0329e68cd8/lungo/system/vault.yaml) for an example).


***Initialize the Vault cluster***

```bash
kubectl exec -n vault vault-0 -- vault operator init \
    -key-shares=1 \
    -key-threshold=1 \
    -format=json > cluster-keys.json

export VAULT_UNSEAL_KEY=$(jq -r ".unseal_keys_b64[]" cluster-keys.json)
kubectl exec -n vault -ti vault-0 -- vault operator unseal $VAULT_UNSEAL_KEY
kubectl exec -n vault -ti vault-1 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec -n vault -ti vault-1 -- vault operator unseal $VAULT_UNSEAL_KEY
kubectl exec -n vault -ti vault-2 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec -n vault -ti vault-2 -- vault operator unseal $VAULT_UNSEAL_KEY
```

You obtain the root token in the `cluster-keys.json` file. Ensure to keep it safe and **do not commit it to the repository** (or encrypt it if you do).

```bash
age -R ~/.ssh/id_ed25519.pub cluster-keys.json > cluster-keys.json.age # Encrypt the file
age -d -i ~/.ssh/id_ed25519 cluster-keys.json.age > cluster-keys.json # Decrypt the file
```

***Create a secret engine in Vault***
```bash 
kubectl port-forward -n vault svc/vault 8200:8200 
```

```bash
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN=$(jq -r ".root_token" cluster-keys.json)
vault secrets enable kv
vault login $(jq -r ".root_token" cluster-keys.json) 
vault kv put kv/foo my-value=s3cr3t
```

## External Secrets

External Secrets allows you to use secrets stored in external secret management systems like AWS Secrets Manager, GCP Secret Manager, Azure Key Vault, and HashiCorp Vault. It is installed in the `external-secrets` namespace using the ArgoCD application `external-secrets` (see [here](https://github.com/qjoly/homelab/blob/3fc5c2fa7269afa87d6800083cbb2a0329e68cd8/lungo/system/external-secret.yaml) for an example).

*Note: This is actually the root token, which is not recommended for production use. In a production environment, you should create a dedicated token with the appropriate policies.*

***Create a secret with the Vault token and note which namespaces are allowed to reflect it***
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
stringData:
  token: $(jq -r ".root_token" cluster-keys.json)
metadata:
  name: vault-token
  namespace: external-secrets
  annotations:
   reflector.v1.k8s.emberstack.com/reflection-allowed: "true"
   reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces: "kube-system,cert-manager-infomaniak,kube-system"
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
EOF
```

### Test the External Secrets


***Create a secret in the default namespace that reflects the secret in the external-secrets namespace***
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: vault-token
  namespace: default
  annotations:
   reflector.v1.k8s.emberstack.com/reflects: "external-secrets/vault-token"
type: Opaque
EOF
```

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





