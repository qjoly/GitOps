#!/bin/bash

# Paramètres du Proxmox
export proxmox_url="https://IP_PROXMOX:8006/api2/json"
export proxmox_node="NOM_NOEUD"
export proxmox_username="root@pam"
export proxmox_password="Password" # Il est préférable d'utiliser un utilisateur dédié à Proxmox
export proxmox_vm_storage="local-zfs"
export proxmox_iso_url="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-11.6.0-amd64-netinst.iso"
export proxmox_iso_checksum="sha256:e482910626b30f9a7de9b0cc142c3d4a079fbfa96110083be1d0b473671ce08d"
export proxmox_iso_storage="local"
export proxmox_network="vmbr0"

# Ressources attribuées à la VM
export vm_id=9002
export vm_name="debian-11-tf"
export template_description="VM debian"
export vm_default_user="root"
export vm_cpu=2
export vm_disk="8G"
export vm_memory=1024

# Paramètres de la VM Template
export prefix_disk="vd"
export ssh_username="root"
export ssh_password="HugePassword"
export userdeploy_password="HugePassword"

export vm_keys=$(echo "$(cat ~/.ssh/id_ed25519.pub)")
#export vm_keys=$(echo "$(cat ./KeyDEPLOY.id_rsa.pub)\n$(cat ./KeyINFRA.id_rsa.pub)\n$(cat ~/.ssh/id_rsa.pub)")

# set variables
j2 http/preseed.cfg.j2 > http/preseed.cfg

#sshpass -p "${proxmox_password}" ssh "${proxmox_ssh}" "wget ${iso_url} -P /var/lib/vz1/template/iso/"
#PACKER_LOG=1 packer build debian-test.json
packer build debian-11-amd64-proxmox.json

rm -f http/preseed.cfg

