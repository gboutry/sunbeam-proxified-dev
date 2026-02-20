locals {
  computed_nodes = [
    for i, vm in module.maas_compute : {
      name           = vm.name
      fqdn           = vm.fqdn
      hostname       = vm.hostname
      ip             = vm.ip
      cores          = vm.cores
      memory         = vm.memory
      root_disk_size = vm.root_disk_size
      nb_osd         = vm.nb_osd
      osd_disk_size  = vm.osd_disk_size
      management_net = "management"
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
  description = "Information about all compute nodes"
  value       = local.computed_nodes
}

output "maas_nodes" {
  description = "MAAS-specific VMs (juju-controller and sunbeam)"
  value = [
    { name = module.maas_juju_controller.name, ip = module.maas_juju_controller.ip, fqdn = module.maas_juju_controller.fqdn, roles = module.maas_juju_controller.roles },
    { name = module.maas_sunbeam.name, ip = module.maas_sunbeam.ip, fqdn = module.maas_sunbeam.fqdn, roles = module.maas_sunbeam.roles },
  ]
}

output "maas_networks" {
  description = "MAAS cloud network bridge names keyed by network type"
  value       = { for k, net in lxd_network.maas_networks : k => net.name }
}
