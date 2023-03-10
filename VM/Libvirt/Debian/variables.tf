variable "provisionning_debian_memory" {
    type        = number
    default     = 1024
    description = "This is another example input variable using env variables."
}

variable "provisionning_debian_cpu" {
    type        = number
    default     = 1
    description = "This is another example input variable using env variables."
}

variable "source_file" {
    type        = string
    default     = "../../artifacts/packer-Debian"
    description = "This is another example input variable using env variables."
}

variable "hypervisor_libvirt_pool_dir" {
    type        = string
    description = "This is another example input variable using env variables."
}

variable "hypervisor_libvirt_pool_name" {
    type        = string
    default     = "clusterOps"
    description = "This is another example input variable using env variables."
}


variable "provisionning_debian_kubernetes_enabled" {
    type        = bool
    default     = false
    description = "This is another example input variable using env variables."
}