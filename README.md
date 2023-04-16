<p align="center">
    <img src="https://avatars.githubusercontent.com/u/82603435?v=4" width="140px" alt="Helm LOGO"/>
    <br>
    <img src="http://readme-typing-svg.herokuapp.com?font=Fira+Code&pause=1000&center=true&width=435&lines=GitOps;D%C3%A9ploiement+Automatis%C3%A9+de+mon+Lab;Terraform%2C+k3s%2C+Packer" alt="Typing SVG" />
</p>

![Nombre de visites](https://visitor-badge.deta.dev/badge?page_id=qjoly.gitops)

![Packer](https://img.shields.io/badge/packer-%23E7EEF0.svg?style=for-the-badge&logo=packer&logoColor=%2302A8EF)![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white)![Git](https://img.shields.io/badge/git-%23F05033.svg?style=for-the-badge&logo=git&logoColor=white)![Ansible](https://img.shields.io/badge/ansible-%231A1918.svg?style=for-the-badge&logo=ansible&logoColor=white)![Flux](https://img.shields.io/badge/flux-%23326ce5.svg?style=for-the-badge&logoColor=white)

# Description du projet

J'utilise Kubernetes dans différents contextes, ma "production" est dans un serveur dédié OVH avec un hyperviseur **Proxmox** tandis que mon Homelab est basé sur **Libvirt**. Afin d'uniformiser mes environnements, j'ai décidé de créer un projet qui me permettrait de déployer rapidement un les mêmes applications sur les deux hyperviseurs.

Le projet est donc scindé en 2 parties, une partie Terraform/Ansible qui permet de déployer l'infrastructure 

# Dépendances
- terraform
- sops (facultatif)
- pre-commit (facultatif)
- yq
- taskfile
- j2cli
- flux (cli)
    
# Démarrer le projet

Les différentes étapes de l'installation sont gérées par Taskfile. Il suffit donc de lancer la commande suivante :
```bash
task general:all
```

Je vous invite à suivre la documentation du projet [ici](https://qjoly.github.io/GitOps/) pour installer les dépendances et créer le fichier de configuration.

# LICENSE

![License](https://img.shields.io/github/license/QJoly/GitOps?style=for-the-badge)