output "compute_nodes" {
  description = "Information about all compute nodes including their network configuration"
  value = [
    for i, vm in module.compute : {
      name            = vm.name
      fqdn            = vm.fqdn
      hostname        = vm.hostname
      ip              = vm.ip
      cores           = vm.cores
      memory          = vm.memory
      root_disk_size  = vm.root_disk_size
      nb_osd          = vm.nb_osd
      osd_disk_size   = vm.osd_disk_size
      management_net  = "restrictedbr0"  # Always connected
      compute_nets    = vm.compute_nets  # Additional networks
      osd_devices     = vm.osds
    }
  ]
}

output "network_topology" {
  description = "Overview of the network topology"
  value = {
    management = {
      name    = lxd_network.restricted.name
      network = local.restricted_net
      domain  = local.restricted_domain
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
