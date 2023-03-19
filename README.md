<p align="center">
    <img src="https://avatars.githubusercontent.com/u/82603435?v=4" width="140px" alt="Helm LOGO"/>
    <br>
    <img src="http://readme-typing-svg.herokuapp.com?font=Fira+Code&pause=1000&center=true&width=435&lines=GitOps;D%C3%A9ploiement+Automatis%C3%A9+de+mon+Lab;Terraform%2C+k3s%2C+Packer" alt="Typing SVG" />
    <br> <br> <br>
    <img src="https://github.com/QJoly/GitOps/blob/main/.github/workflows/wip.png?raw=true" alt="Work in Progress">
</p>

![Nombre de visites](https://visitor-badge.deta.dev/badge?page_id=qjoly.gitops)

# Description du projet

J'utilise Kubernetes dans différents contextes, ma "production" est dans un serveur dédié OVH avec un hyperviseur **Proxmox** tandis que mon Homelab est basé sur **Libvirt**. Afin d'uniformiser mes environnements, j'ai décidé de créer ce projet pour déployer les mêmes environnements *(k3s)* dans des hyperviseurs différents.

# Dépendances
- terraform
- sops (facultatif)
- pre-commit (facultatif)
- yq 
- taskfile
- j2cli

# TODO

- Packer : 
    - [x] Installation de Debian sous Libvirt
    - [ ] Installation de Debian sous Proxmox
- Terraform :
    - [x] Création de l'infrastructure sur Libvirt
    - [ ] Création de l'infrastructure sur Proxmox
- Kubernetes :
    - [x] Déploiement de Kubernetes avec [k3s-ansible](https://github.com/k3s-io/k3s-ansible)
    - [x] Récupération du fichier *kubeconfig*
    - [ ] Installation de Flux
    - [ ] Configuration de Flux
- Documentation : 
    - [ ] Configuration Libvirt
    - [ ] Résolution d'erreur Libvirt
    

# Troubleshooting

## EnvironmentFilter from jinja2
During Ansible:
```
Cannot import name 'environmentfilter' from 'jinja2'
```
You **can't** install Ansible using *apt*, you'll get an old version with a lot of deprecated dependencies. Please install Ansible using pip install : 
`python3 -m pip install --user ansible`


## Ipv6 instead of ipv4
```
│ TASK [Gathering Facts] *********************************************************
│ fatal: [kube-0-tf]: UNREACHABLE! => {"changed": false, "msg": "Failed to connect to the host via ssh: ssh: connect to host fe80::5054:ff:fec2:1c4 port 22: Invalid argument", "unreachable": true}
│ ok: [kube-2-tf]
│ ok: [kube-1-tf]
```