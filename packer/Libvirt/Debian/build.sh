#!/bin/bash

#vm caracteristiques
export vm_name="debian-11-tf"
export template_description="VM debian"
export vm_default_user="root"
export vm_cpu=2
export vm_disk="8G"
export vm_memory=4096

export iso_url="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-11.6.0-amd64-netinst.iso"
export iso_checksum="sha256:e482910626b30f9a7de9b0cc142c3d4a079fbfa96110083be1d0b473671ce08d"

# VM root login & deploy user
export prefix_disk="vd"
export ssh_username="root"
export ssh_password="HugePassword"
export userdeploy_password="HugePassword"

export vm_keys=$(echo "$(cat ~/.ssh/id_ed25519.pub)")
#export vm_keys=$(echo "$(cat ./KeyDEPLOY.id_rsa.pub)\n$(cat ./KeyINFRA.id_rsa.pub)\n$(cat ~/.ssh/id_rsa.pub)")

# set variables
j2 http/preseed.cfg.j2 > http/preseed.cfg

packer build debian-11-amd64-libvirt.json

rm -f http/preseed.cfg


