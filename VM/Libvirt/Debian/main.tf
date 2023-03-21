
resource "libvirt_pool" "cluster" {
  name = var.hypervisor_libvirt_pool_name
  type = "dir"
  path = var.hypervisor_libvirt_pool_dir
}

module "node" {
  count             = var.provisionning_debian_kubernetes_nodes
  source            = "./modules/libvirt-qemu"
  node_name         = "kube-${count.index}-tf"
  node_memory       = var.provisionning_debian_memory
  node_vcpu         = var.provisionning_debian_cpu
  source_file       = var.source_file
  pool_name         = var.hypervisor_libvirt_pool_name
  depends_on = [
    libvirt_pool.cluster
  ]
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