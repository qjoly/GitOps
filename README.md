<p align="center">
    <img src="https://avatars.githubusercontent.com/u/82603435?v=4" width="140px" alt="Helm LOGO"/>
    <br>
    <img src="https://readme-typing-svg.herokuapp.com?font=Fira+Code&pause=1000&center=true&vCenter=true&width=435&lines=GitOps;deployer-un-k3s;deployer-un-pfsense;deployer-un-proxmox" alt="Typing SVG" />
</p>

![Nombre de visites](https://visitor-badge.deta.dev/badge?page_id=qjoly.gitops)

# TODO

- Gestion des secrets par Terraform via du YAML
- Gestion des secrets par Packer via du YAML
- Créer un taskfile pour lancer les étapes de manières séquentielles
- Créer les premiers terraforms
- Générer le mot de passe dans le preseed de Debian
- Gerer variables d’env avec Packer

pour copier clé publique dans debian : 
task: 
    - recup dans variable le contenu de $vmtemplate_debian_ssh_key
    - faire le templating du preseed

# Requirements
- terraform
- sops (optional)
- pre-commit (optional)
- yq 
- taskfile
- j2cli
