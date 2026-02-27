locals {
  # Which network types each role needs for OpenStack traffic isolation.
  # Keys match local.maas_network_configs in networking.tf.
  maas_role_to_net_types = {
    control = ["internal", "public", "storage"]
    compute = ["internal", "data", "storage"]
    storage = ["internal", "storage", "storage-cluster"]
    network = ["internal", "data"]
  }

  # CIDR lookup by network type — derived from variables so user overrides are respected.
  net_type_to_cidr = { for k, v in local.maas_network_configs : k => v.cidr }

  # Per-VM list of isolation CIDRs, deduped, derived from the VM's roles.
  vm_isolation_cidrs = [
    for i in range(var.nb_vm) : distinct(flatten([
      for role in try(var.vm_config_override["vm${i}"].roles, var.vm_config.roles) :
      [for net_type in lookup(local.maas_role_to_net_types, role, []) :
        local.net_type_to_cidr[net_type]
      ]
    ]))
  ]
}

module "maas_compute" {
  count      = var.nb_vm
  depends_on = [maas_vm_host.lxd]
  source     = "../modules/maas_compute"

  hostname               = "bm${count.index}"
  management_domain      = var.management_domain
  management_subnet_cidr = "10.10.10.0/24"
  management_ip          = cidrhost("10.10.10.0/24", 83 + count.index)
  vm_host                = maas_vm_host.lxd.id
  cores                  = try(var.vm_config_override["vm${count.index}"].cores, var.vm_config.cores)
  memory                 = try(var.vm_config_override["vm${count.index}"].memory, var.vm_config.memory)
  root_disk_size         = try(var.vm_config_override["vm${count.index}"].root_disk_size, var.vm_config.root_disk_size)
  nb_osd                 = try(var.vm_config_override["vm${count.index}"].nb_osd, var.vm_config.nb_osd)
  osd_disk_size          = try(var.vm_config_override["vm${count.index}"].osd_disk_size, var.vm_config.osd_disk_size)
  roles                  = try(var.vm_config_override["vm${count.index}"].roles, var.vm_config.roles)
  isolation_cidrs        = local.vm_isolation_cidrs[count.index]
}
