Si vous voulez utiliser mon projet, je vous invite à créer un Fork sur un dépôt Git qui vous appartient.

Une fois le dépôt copié, il suffira de modifier l'URL utilisée par *Flux* durant le déploiement dans les fichiers `./kubernetes/flux-system/GitRepository` et `./kubernetes/flux-system/kustomization-git.yml`.

```yml
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: GitRepository
metadata:
  name: qjoly
  namespace: flux-system
spec:
  interval: 1m0s
  url: https://github.com/qjoly/GitOps
  ref:
    branch: main
```
```yml
apiVersion: kustomize.toolkit.fluxcd.io/v1beta2
kind: Kustomization
metadata:
  name: qjoly
  namespace: flux-system
spec:
  interval: 5m0s
  path: ./kubernetes
  prune: true
  sourceRef:
    kind: GitRepository
    name: qjoly
```