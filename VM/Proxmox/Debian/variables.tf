variable "provisionning_debian_memory" {
    type        = number
    default     = 1024
    description = "Quantity of RAM (in Mo) for each node."
}

variable "vmtemplate_debian_username" {
    type        = string
    default     = "utilisateur"
    description = "admin username for the VM."
}

variable "provisionning_debian_cpu" {
    type        = number
    default     = 1
    description = "Number of CPU for each node."
}

variable "hypervisor_proxmox_vm_network" {
    type        = string
    default     = "vmbr0"
    description = "Network interface that will be used as bridge"
}

variable "provisionning_debian_kubernetes_nodes" {
    type        = string
    default     = 2
    description = "Number of nodes that will be created."
}

variable "provisionning_debian_kubernetes_enabled" {
    type        = bool
    default     = false
    description = "If true, Terrafom will run the Ansible Playbook that install the cluster"
}

variable "vmtemplate_debian_name" {
    type        = string
    default     = "Debian"
    description = "VM that will be cloned."
}

variable "hypervisor_proxmox_vm_storage" {
    type        = string
    default     = "local-zfs"
    description = "Storage that will store the VM."
}

variable "vmtemplate_debian_disk_size" {
    type        = string
    default     = "32G"
    description = "Storage that will store the VM."
}

variable "hypervisor_proxmox_node" {
    type        = string
    default     = "pve"
    description = "Proxmox Node."
}

variable "hypervisor_proxmox_node_url" {
    type        = string
    default     = "http://192.168.1.100:8006/api2/json"
    description = "Proxmox URL"
}

variable "hypervisor_proxmox_username" {
    type        = string
    default     = "root@pam"
    description = "Proxmox Username"
}

variable "hypervisor_proxmox_password" {
    type        = string
    default     = "RootPassword"
    description = "Proxmox Pass"
}

variable "hypervisor_proxmox_vm_pool" {
    type        = string
    default     = ""
    description = "Proxmox pool"
}