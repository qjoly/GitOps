resource "libvirt_volume" "node_disk" {
  name = "${var.node_name}.qcow2"
  pool = "${var.pool_name}"
  source = "${var.source_file}"
  format = "qcow2"
}

resource "libvirt_domain" "node" {
  name   = "${var.node_name}"
  memory = "${var.node_memory}"
  vcpu   = "${var.node_vcpu}"

  network_interface {
    network_name = "default"
    wait_for_lease = true
  }

  autostart = true
  qemu_agent = true

  disk {
    volume_id = "${libvirt_volume.node_disk.id}"
  }

  console {
    type = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type = "spice"
    listen_type = "address"
    autoport = true
  }
  
  provisioner "local-exec" {
    when    = create
    command = "echo \"The IP of vm '${self.name}' is '${self.network_interface[0].addresses[0]}'\""
  }
}

output "node_ip" {
  depends_on = [libvirt_domain.node]
  value = "${libvirt_domain.node.network_interface[0].addresses[0]}"
}


output "node_name" {
  depends_on = [libvirt_domain.node]
  value = "${libvirt_domain.node.name}"
}


