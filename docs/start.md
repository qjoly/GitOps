
Avant de lancer la commande `task` qui va exécuter les tâches une-par-une, il convient de vérifier que les dépendances soient présentes sur votre machine.

La page permettant d'installer les dépendances est accessible [ici](../dep/)

## Configuration

Avant de lancer la tâche permettant de lancer les étapes à la suite. Il est nécessaire de configurer les fichiers suivants :

- `Taskfile.yaml`
- `secret.dev.yaml`

### Taskfile

Dans le fichier `Taskfile.yaml`, voici les variables à éditer :

```yml
vars:
  secret_file: ./secret.dev.yaml
  hypervisor: Libvirt
  distribution: Debian 
```

- `secret_file` renvoie vers le fichier contenant les variables nécessaire à Packer et Terraform.
- `hypervisor` permet à task de lancer Terraform/Packer dans des contextes différents : (ex:`VM/Libvirt` pour Terraform si l'hyperviseur est `Libvirt`).
*Pour l'instant, je n'ai prévu que Proxmox et Libvirt.*
- `distribution` fonctionne d'une manière identique à `hypervisor` : permet à Packer/Terraform de trouver des contextes adaptés (ex:`VM/Libvirt/Debian` si l'hyperviseur est `Libvirt` et la distribution est `Debian`)

### SecretFile

Voici un fichier `secret.dev.yml` fonctionnel:

```yaml
vmtemplate:
    debian:
        enabled: true
        id: 9001 # Only for Proxmox
        name: Debian
        root_password: rootpassword
        username: utilisateur
        password: pass
        # Depending of the format of the disk
        disk_prefix: vd
        cpu: 2
        memory: 1024
        # Only absolute path
        ssh_key: /home/kiko/.ssh/id_ed25519.pub
        disk_size: 8192
        iso:
            url: https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-11.6.0-amd64-netinst.iso
            checksum: sha512:224cd98011b9184e49f858a46096c6ff4894adff8945ce89b194541afdfd93b73b4666b0705234bd4dff42c0a914fdb6037dd0982efb5813e8a553d8e92e6f51
hypervisor:
    libvirt:
        pool_dir: ~/.libvirt/pool
        pool_name: cluster
        # Libvirt will use qemu:///system as URI
provisionning:
    debian:
        enabled: true
        cpu: 2
        memory: 1024
        # Only compatible for Debian, Alpine is not yet supported by k3s-ansible
        kubernetes:
            enabled: true
            nodes: 2
```

Par défaut, ce fichier va déployer 2 machines virtuelles et lancer le rôle `k3s-ansible` pour installer Kubernetes

## Lancer le projet 

### Méthode automatique

Pour lancer les différentes étapes à la suite, il suffit de lancer la commande :

```bash
task general:all
```

Résultat de la commande :
<script async id="asciicast-W1I0WheIlBW2pWPSfclnfTTAD" src="https://asciinema.org/a/W1I0WheIlBW2pWPSfclnfTTAD.js"></script>

### Méthode manuelle

Il est également possible de lancer les étapes une-par-une en utilisant *task*.

En utilisant la commande `task -l`, vous verrez les différentes actions configurées:

```bash
task: Available tasks for this project:
* general:all:                     Run every task
* general:clean:                   Clean everything
* general:env:                     Generate dotenv file
* general:prepare-ansible:         clone k3s-ansible if needed
* kubernetes:check-flux-pre:       Check if flux can be installed
* kubernetes:configure-flux:       Check if flux can be installed
* kubernetes:fetch_config:         Download the kubeconfig of master
* kubernetes:install-flux:         Check if flux can be installed
* kubernetes:pods:                 Get all running pods
* packer:debian:                   Run Debian-Packer
* terraform:alpine:                Running Alpine terraform
* terraform:debian:                Running Debian terraform
* terraform:destroy-debian:        Running Debian terraform
* terraform:provisioning:          Launch Terraform
```

Voici les étapes lancées dans l'ordre :

- general:env
- general:prepare-ansible
- packer:debian
- terraform:provisioning
- kubernetes:fetch_config
- kubernetes:check-flux-pre
- kubernetes:install-flux
