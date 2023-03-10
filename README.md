<p align="center">
    <img src="https://avatars.githubusercontent.com/u/82603435?v=4" width="140px" alt="Helm LOGO"/>
    <br>
    <img src="https://readme-typing-svg.herokuapp.com?font=Fira+Code&pause=1000&center=true&vCenter=true&width=435&lines=GitOps;deployer-un-k3s;deployer-un-pfsense;deployer-un-proxmox" alt="Typing SVG" />
</p>

![Nombre de visites](https://visitor-badge.deta.dev/badge?page_id=qjoly.gitops)

# TODO

Kubernetes :
    - Récupérer le kubeconfig

# Requirements
- terraform
- sops (optional)
- pre-commit (optional)
- yq 
- taskfile
- j2cli

# Libvirt

- Créer/utiliser un groupe pour le daemon libvirt (`unix_sock_group = "libvirt"` dans `/etc/libvirt/libvirtd.conf`)


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