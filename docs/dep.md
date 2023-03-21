

La plupart des dépendances peuvent s'installer dans votre répertoire home *(dans le dossier `~/.local/bin`)*.
Je vous recommande **fortement** d'ajouter de manière permanente ce dossier dans votre variable d'environnement `$PATH`.

Pour cela, ajoutez la ligne suivante dans votre fichier `~/.bashrc` pour Bash, ou `~/.zshrc` pour Zsh.

## Installation de Terraform

Le détail de l'installation est disponible sur le site officiel de Hashicorp ([lien ici](https://developer.hashicorp.com/terraform/downloads?product_intent=terraform))

### Ubuntu / Debian
```bash
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```

### Linux
```bash
wget https://releases.hashicorp.com/terraform/1.4.2/terraform_1.4.2_linux_amd64.zip -O- | gunzip -c - > terraform
chmod +x ./terraform
mkdir -p ~/.local/bin
mv ./terraform ~/.local/bin/terraform
export PATH=$PATH:~/.local/bin/
```

Pour vérifier que Terraform est bien installé, lancez la commande `terraform -version`.


## Installation de Packer

Le détail de l'installation est disponible sur le site officiel de Hashicorp ([lien ici](https://developer.hashicorp.com/packer/downloads))

### Ubuntu / Debian
```bash
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install packer
```

### Linux
```bash
wget https://releases.hashicorp.com/packer/1.8.6/packer_1.8.6_linux_amd64.zip -O- | gunzip -c - > terraform
chmod +x ./packer
mkdir -p ~/.local/bin
mv ./packer ~/.local/bin/packer
export PATH=$PATH:~/.local/bin/
```

Pour vérifiez que Packer est bien installé, lancez la commande `packer -version`.
# J2Cli
**j2cli** est la version 'ligne de commande' de l'outil *[Jinja2](https://jinja.palletsprojects.com)* permettant de créer des contenus dynamiques dans des fichiers textuels. Dans le projet `GitOps`, nous l'utilisons pour faire du remplacement dans les fichiers `preseed.cfg` durant l'installation de Debian.

Il sera nécéssaire d'avoir *Python3* et *Pip* installé sur votre système. Si ce n'est pas le cas, je vous invite à consulter [cette page](https://pip.pypa.io/en/stable/installation/).

```
python3 -m pip install j2cli
export PATH=$PATH:~/.local/bin/
```

Pour vérifier que j2cli est bien installé, lancez la commande `j2 -v`.

# Installation de yq

*YQ* est un utilitaire permettant d'interagir avec les fichiers `.yaml` et `.json` depuis la CLI *Bash*. Nous l'utilisons pour convertir le fichier `secret.dev.yaml` en `.env`.

```bash
mkdir -p ~/.local/bin
wget https://github.com/mikefarah/yq/releases/download/v4.32.2/yq_linux_amd64 -O ~/.local/bin/yq
chmod +x ~/.local/bin/yq
export PATH=$PATH:~/.local/bin/
```

Pour vérifier que YQ est bien installé, lancez la commande `yq --version`.


# Installation de Taskfile

Taskfile est un utilitaire remplaçant les fichiers `Makefile`.

## Ubuntu / Debian
```bash
wget https://github.com/go-task/task/releases/download/v3.22.0/task_linux_amd64.deb
sudo dpkg -i task_linux_amd64.deb
```

## Linux
```bash
mkdir -p ~/.local/bin
wget https://github.com/go-task/task/releases/download/v3.22.0/task_linux_amd64.tar.gz | tar xvfz -
mv ./task ~/.local/bin/task
export PATH=$PATH:~/.local/bin/
```

Pour vérifier que Taskfile est bien installé, lancez la commande `task --version`.
 
# Installation de Flux

```bash
mkdir -p ~/.local/bin
wget https://github.com/fluxcd/flux2/releases/download/v0.41.1/flux_0.41.1_linux_amd64.tar.gz -O - | tar xvfz -
mv ./flux ~/.local/bin/flux
export PATH=$PATH:~/.local/bin/
```

Pour vérifier que Flux est bien installé, lancez la commande `flux --version`.

# Installation de SOPS (Faculatif)

SOPS est un outil permettant de chiffrer des sections dans des **YML, JSON, INI**. Je l'utilise pour stocker des secrets dans mon dépôt qui seront indéchiffrables sans ma clé *Age*.

L'usage de SOPS est **facultatif**. Vous pouvez très bien créer votre fichier *secret.\*.yaml* sans chiffrer.

```bash
wget https://github.com/mozilla/sops/releases/download/v3.7.3/sops-v3.7.3.linux -O- | gunzip -c - > sops
chmod +x ./sops
mkdir -p ~/.local/bin
mv ./sops ~/.local/bin/sops
export PATH=$PATH:~/.local/bin/
```

Vous trouverez un exemple d'utilisation de Sops et Age sur [cette page](../sops/)

# Installation de Pre-Commit (Faculatif)

Pre-Commit nous permet de créer un Hook sur *Git* qui va effectuer des actions avant de commit nos modifications.

Dans le contexte de ce projet, pre-commit permet de chiffrer certaines variables dans les fichiers de configuration *(ex: `secret.dev.yaml`)*.

```bash
python3 -m pip install pre-commit
export PATH=$PATH:~/.local/bin/
```