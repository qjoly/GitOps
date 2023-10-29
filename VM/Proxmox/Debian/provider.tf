terraform {
  required_providers {
    proxmox = {
      source = "Telmate/proxmox"
      version = "2.9.14"
    }
  }
}

provider "proxmox" {
  pm_api_url = var.hypervisor_proxmox_node_url
  pm_user    = var.hypervisor_proxmox_username
  pm_password = var.hypervisor_proxmox_password
  pm_tls_insecure = "true"
  pm_parallel     = 2
}