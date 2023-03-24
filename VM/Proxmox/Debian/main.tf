
module "node" {
  count             = var.provisionning_debian_kubernetes_nodes
  source            = "QJoly/proxmox/module"
  version           = "0.0.1"
  node_name         = "kube-${count.index}-tf"
  node_target       = var.hypervisor_proxmox_node
  node_qemuga       = 1
  node_pool         = var.hypervisor_proxmox_vm_pool
  node_size_disk    = "${var.vmtemplate_debian_disk_size}M"
  node_bootauto     = true
  node_template     = var.vmtemplate_debian_name
  node_storage_disk = var.hypervisor_proxmox_vm_storage
  node_network_host = var.hypervisor_proxmox_vm_network
  node_notes        = "Super-VM for the customer No 01"
  node_cpu          = var.provisionning_debian_cpu
  node_memory       = var.provisionning_debian_memory
}

resource "local_file" "inventory" {
  filename = "./inventory.ini"
  content = <<_EOF
[master]
${module.node[0].node_name} ansible_host=${module.node[0].node_ip}
%{if length(module.node) > 1}
[node]
%{for item in slice(module.node.*, 1, length(module.node))~}
${item.node_name} ansible_host=${item.node_ip}
%{endfor}
%{endif}
[k3s_cluster:children]
master
node
_EOF
  depends_on = [module.node]
}

resource "local_file" "master" {
  filename = "../../../artifacts/master"
  content = <<_EOF
${module.node[0].node_ip}
_EOF

  depends_on = [module.node]
}

resource "null_resource" "playbooks" {
  count = var.provisionning_debian_kubernetes_enabled ? 1 : 0
  
  depends_on = [module.node, local_file.inventory]

  provisioner "local-exec" {
    when    = create
    command = "ANSIBLE_FORCE_COLOR=true ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook --timeout 30 -i inventory.ini ${path.cwd}/../../Ansible/set_hostname.yml -v"
  }

  provisioner "local-exec" {
    when    = create
    command = "ANSIBLE_FORCE_COLOR=true ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook --timeout 30 -i inventory.ini ${path.cwd}/../../Ansible/k3s/site.yml -v -e ansible_user=utilisateur"
  }
}