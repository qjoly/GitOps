<p align="center">
    <img src="https://avatars.githubusercontent.com/u/82603435?v=4" width="140px" alt="Helm LOGO"/>
    <br>
    <img src="http://readme-typing-svg.herokuapp.com?font=Fira+Code&pause=1000&center=true&width=435&lines=GitOps;D%C3%A9ploiement+Automatis%C3%A9+de+mon+Lab;Terraform%2C+k3s%2C+Packer" alt="Typing SVG" />
</p>

<div align="center">

  [![Blog](https://img.shields.io/badge/Blog-blue?style=for-the-badge&logo=buymeacoffee&logoColor=white)](https://une-tasse-de.cafe/)
  [![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.28.3-blue?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kubernetes.io/)
  [![Linux](https://img.shields.io/badge/Talos-v1.6.0-blue?style=for-the-badge&logo=linux&logoColor=white)](https://kubernetes.io/)

</div>


# GitOps

Github repository where I manage my labs.

## Clusters

### Cloud

| Node          | Type          | IP              | OS           | RAM  | Cores | Architecture | Notes |
|---------------|---------------|-----------------|--------------|------|-------|--------------|-------|
| talos-0ya-z8j | Control-plane | 192.168.128.10  | Talos v1.6.0 | 3 Go | 2     | Amd64        |       |
| talos-4n2-efl | Control-plane | 192.168.128.91  | Talos v1.6.0 | 3 Go | 2     | Amd64        |       |
| talos-th0-iv8 | Control-plane | 192.168.128.37  | Talos v1.6.0 | 3 Go | 2     | Amd64        |       |
| talos-i2b-uua | Worker        | 192.168.128.114 | Talos v1.6.0 | 3 Go | 2     | Amd64        |       |
| talos-jmc-u9l | Worker        | 192.168.128.106 | Talos v1.6.0 | 3 Go | 2     | Amd64        |       |
| talos-v1m-53q | Worker        | 192.168.128.100 | Talos v1.6.0 | 3 Go | 2     | Amd64        |       |

### Home

## Version Talos

<img src="https://www.talos.dev/images/logo.svg" width="100px">

Pour un déploiement baremetal, j'ai choisi d'utiliser Talos. Talos est un système d'exploitation pour Kubernetes. Il est conçu pour être sécurisé par défaut, simplifier les opérations et être facilement extensible.

La configuration de Talos est gérée par des fichiers YAML dans le répertoire `talos`. Pour déployer Talos, il suffit de lancer la commande suivante :

```bash
cd talos/
CONTROLPLANE=("192.168.128.10" "192.168.128.91" "192.168.128.37")
for node in $CONTROLPLANE; do
    talosctl apply-config --insecure -n $node -e $node --file controlplane.yaml
done

WORKER=("192.168.128.100" "192.168.128.106" "192.168.128.114")
for node in $WORKER; do
    talosctl apply-config --insecure -n $node -e $node --file worker.yaml
done
```

Les fichiers de configuration de Talos vont également installer [Cilium](https://cilium.io).

## Version Packer/Terraform

Je dispose de plusieurs machines virtuelles sur lesquelles je souhaite déployer un cluster Kubernetes. Pour cela, j'ai décidé d'utiliser Terraform pour déployer l'infrastructure, Packer pour créer les images, Ansible pour provisionner les machines et Flux pour déployer les applications.

### Dépendances
- terraform
- sops (facultatif)
- pre-commit (facultatif)
- yq
- taskfile
- j2cli
- flux (cli)
    
### Démarrer le projet

Les différentes étapes de l'installation sont gérées par Taskfile. Il suffit donc de lancer la commande suivante :
```bash
task general:all
```

Je vous invite à suivre la documentation du projet [ici](https://qjoly.github.io/GitOps/) pour installer les dépendances et créer le fichier de configuration.

# LICENSE

![License](https://img.shields.io/github/license/QJoly/GitOps?style=for-the-badge)
