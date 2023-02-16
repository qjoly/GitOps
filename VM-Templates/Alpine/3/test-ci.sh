#!/bin/sh
export ssh_password=fakepassword
export proxmox_password=user
export proxmox_user=pass
export proxmox_node=local
export proxmox_url=https://localhost:8006
export bridge="vmbr0"
export storage_name="local"

packer validate *.json

