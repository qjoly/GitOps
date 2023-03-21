Todo:
- pre-commit
- yq 
- taskfile
- flux

# Installation de Terraform

Le détail de l'installation est disponible sur le site officiel de Hashicorp ([lien ici](https://developer.hashicorp.com/terraform/downloads?product_intent=terraform))

## Ubuntu / Debian
```bash
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```

## Linux
```bash
wget https://releases.hashicorp.com/terraform/1.4.2/terraform_1.4.2_linux_amd64.zip -O- | gunzip -c - > terraform
chmod +x ./terraform
mkdir -p ~/.local/bin
mv ./terraform ~/.local/bin/terraform
export PATH=$PATH:~/.local/bin/
```

Pour vérifier que Terraform est bien installé, lancez la commande `terraform -version`.


# Installation de Packer

Le détail de l'installation est disponible sur le site officiel de Hashicorp ([lien ici](https://developer.hashicorp.com/packer/downloads))

## Ubuntu / Debian
```bash
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install packer
```

## Linux
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

## Linux

Il sera nécéssaire d'avoir *Python3* et *Pip* installé sur votre système. Si ce n'est pas le cas, je vous invite à consulter [cette page](https://pip.pypa.io/en/stable/installation/).

```
python3 -m pip install j2cli
export PATH=$PATH:~/.local/bin/
```

Pour vérifier que j2cli est bien installé, lancez la commande `j2 -v`.

# SOPS

```bash
wget https://github.com/mozilla/sops/releases/download/v3.7.3/sops-v3.7.3.linux -O- | gunzip -c - > sops
chmod +x ./sops
mkdir -p ~/.local/bin
mv ./sops ~/.local/bin/sops
export PATH=$PATH:~/.local/bin/
```