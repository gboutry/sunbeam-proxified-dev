locals {
  computed_nodes = [
    for i, vm in module.manual_compute : {
      name           = vm.name
      fqdn           = vm.fqdn
      hostname       = vm.hostname
      ip             = vm.ip
      cores          = vm.cores
      memory         = vm.memory
      root_disk_size = vm.root_disk_size
      nb_osd         = vm.nb_osd
      osd_disk_size  = vm.osd_disk_size
      management_net = "restrictedbr0"
      compute_nets   = vm.compute_nets
      osd_devices    = vm.osds
      roles          = vm.roles
    }
  ]
}

output "ssh_public_key" {
  description = "SSH public key for access"
  value       = trimspace(tls_private_key.global.public_key_openssh)
}

output "ssh_private_key" {
  description = "SSH private key for access"
  value       = trimspace(tls_private_key.global.private_key_pem)
  sensitive   = true
}

output "compute_nodes" {
  description = "Information about all compute nodes including their network configuration"
  value       = local.computed_nodes
}

output "network_topology" {
  description = "Overview of the network topology"
  value = {
    management = {
      name    = lxd_network.restricted.name
      network = local.restricted_net
      domain  = local.restricted_domain
      dns_ip  = local.restricted_dns_ip
    }
    compute_networks = [
      for i, net in lxd_network.computes : {
        name    = net.name
        network = local.compute_nets[i]
      }
    ]
  }
}

output "compute_network_names" {
  description = "Available compute network names for use in vm_config"
  value = [
    for net in lxd_network.computes : net.name
  ]
}
