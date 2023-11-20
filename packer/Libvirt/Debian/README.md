# Packer Debian-11 qemu

## Objectif

Déployer une machine “template” sur qemu. L’idée est de créer une machine respectant une configuration précise pour y réaliser des déploiements automatiques ou différents tests. 
La machine se déploie à l’aide d’un Preseed (template *Jinja2* dans http/preseed.cfg.j2) qui va configurer le minimum requis : 
- Un utilisateur root (accessible via ssh)
- Ansible
- des packages basiques (vim, python etc..)

## Getting Started
### Pré-Requis
- qemu-system-x86_64 (>4.2.1) 
- libvirt (>6.0.0)
- [Packer (1.8.0)](https://www.packer.io/downloads)
- Ansible (2.9.6)
- j2cli (0.3.10)

#### Installer j2cli

    python3 -m pip install --user j2cli
Ajouter \~/.local/bin à son $PATH (pour utiliser les binaires gérés par pip)

    export PATH=$PATH:~/.local/bin/

### Lancer le projet

Générer une clé ($HOME/.ssh/id_rsa) ou modifier le fichier *build.sh* pour y mettre l’emplacement de la clé SSH utilisée par l’utilisateur démarrant le script.

    ssh-keygen -t rsa -b 4096 
    ./build.sh


# TroubleShooting
## No matching host key type found
Si vous êtes sur Ubuntu, vous devrez ajouter le ssh-rsa en algorithme de chiffrement compatible. 
Voici l’erreur sur laquelle vous tomberez : 
```
    proxmox: fatal: [default]: UNREACHABLE! => {"changed": false, "msg": "Failed to connect to the host via ssh: Unable to negotiate with 127.0.0.1 port 32985: no matching host key type found. Their offer: ssh-rsa", "unreachable": true}
```

La solution est d’accepter cet algorithme dans votre fichier `~/.ssh/config`.
```
Host 127.0.0.1
  HostKeyAlgorithms +ssh-rsa
  PubkeyAcceptedAlgorithms +ssh-rsa
```