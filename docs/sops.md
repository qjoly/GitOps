
**Article résumant Sops et son age disponible: [ici](https://une-tasse-de.cafe/blog/sops/)**

Sops est un outil permettant de chiffrer des fichiers de configuration. Celui-ci utilise une méthode de chiffrement asymétrique, c'est-à-dire qu'il utilise une clé publique pour chiffrer et une clé privée pour déchiffrer. Cela permet de chiffrer des fichiers de configuration et de les partager avec d'autres personnes sans avoir à partager la clé privée.

Mon projet GitOps utilise Sops pour chiffrer le fichier principal de configuration `secret.*.yaml`. Il est recommandé d'avoir **deux** clés différentes: l'une pour le déploiement Packer/Terraform, l'autre pour le déploiement sur Kubernetes via FluxCD.

**Il est toutefois possible d'utiliser la même clé pour les deux déploiements.**

## Création des clés de chiffrement

J'utilise Age pour générer les clés de chiffrement. Age est un outil permettant de générer des clés de chiffrement asymétrique.

### Clé de chiffrement pour Packer/Terraform

```bash
# Génération de la clé de chiffrement pour Packer/Terraform
mkdir ~/.age/
age-keygen -o ~/.age/packer-terraform.key
export SOPS_AGE_KEY_FILE=~/.age/packer-terraform.key
```

### Clé de chiffrement pour FluxCD

Il faut placer la clé de chiffrement à l'emplacement `.secrets/age` du dépôt GitOps.

Vous pouvez alors reprendre la même clé de chiffrement que pour Packer/Terraform ou en générer une nouvelle.

```bash
cp ~/.age/packer-terraform.key .secrets/age
# OU
task kubernetes:create-age-key
```
## Configurer cette clé
      - cmd: task kubernetes:create-age-key
        ignore_error: true
      - task kubernetes:create-age-secret
      - task kubernetes:configure-sops-with-age-key

Lancer la tache `kubernetes:create-age-secret` pour créer un secret Kubernetes contenant la clé de chiffrement.

```bash
task kubernetes:create-age-secret
```

Pour configurer le fichier `kubernetes/.sops.yaml` avec la clé de chiffrement, lancer la tache `kubernetes:configure-sops-with-age-key`.

**Ne pas oublier de commiter les changements 