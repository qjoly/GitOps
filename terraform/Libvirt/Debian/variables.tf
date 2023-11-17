variable "provisionning_debian_memory" {
    type        = number
    default     = 1024
    description = "Quantity of RAM (in Mo) for each node."
}

variable "provisionning_debian_cpu" {
    type        = number
    default     = 1
    description = "Number of CPU for each node."
}

variable "source_file" {
    type        = string
    default     = "../../artifacts/packer-Debian"
    description = "Packer file to provision virtual machines."
}

variable "hypervisor_libvirt_pool_dir" {
    type        = string
    description = "Directory that will store virtual disks."
}

variable "hypervisor_libvirt_pool_name" {
    type        = string
    default     = "clusterOps"
    description = "Name of the Libvirt pool that will be created."
}

variable "provisionning_debian_kubernetes_enabled" {
    type        = bool
    default     = false
    description = "If true, Terrafom will run the Ansible Playbook that install the cluster"
}

variable "provisionning_debian_kubernetes_nodes" {
    type        = string
    default     = 2
    description = "Number of nodes that will be created."
}