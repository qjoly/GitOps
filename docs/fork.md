## 1. Forker le dépôt

Pour reprendre ce projet, il faut commencer par le forker. Vous pouvez utiliser la branche `template` qui propose une version sans chiffrement des secrets. 

## 2. Installer le cluster

Créer le fichier `./secret.dev.yaml` à partir du fichier `./secret.dev.yaml.template` et renseigner les valeurs en fonction de votre environnement.

```bash
cp ./secret.dev.yaml.template ./secret.dev.yaml
```

## 3. Modifier configuration de Flux
Si vous voulez utiliser mon projet, je vous invite à créer un Fork sur un dépôt Git qui vous appartient.

Une fois le dépôt copié, il suffira de modifier l'URL utilisée par *Flux* durant le déploiement dans le fichier `./cluster/flux-system/GitRepository`.

## 4. Configurer SOPS

[Voir la page sur SOPS.](https://qjoly.github.io/GitOps/sops/)