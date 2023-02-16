#!/bin/bash

# Paramètres du Proxmox
export proxmox_url="https://192.168.1.210:8006/api2/json"
export proxmox_node="pve"
export proxmox_username="root@pam"
export proxmox_password="GimmeLife" # Il est préférable d'utiliser un utilisateur dédié à Proxmox
export proxmox_vm_storage="local-zfs"
export proxmox_iso_url="https://dl-cdn.alpinelinux.org/alpine/v3.17/releases/x86_64/alpine-virt-3.17.1-x86_64.iso"
export proxmox_iso_checksum="sha256:19d22173b53cd169f65db08a966b51f9ef02750a621902d0d784195d7251b83b"
export proxmox_iso_storage="local"
export proxmox_network="vmbr0"

# Ressources attribuées à la VM
export vm_id=9002
export vm_name="alpine3-11-tf"
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

rm http/authorized_keys || true
for f in ssh/*.pub; do
        name_of_key=$(echo $f | cut -d "/" -f2 )
	echo -e "#$name_of_key" >> http/authorized_keys 
	key=$(cat $f)
	echo -e "$key" >> http/authorized_keys
done

packer build alpine-3-amd64-proxmox.json
