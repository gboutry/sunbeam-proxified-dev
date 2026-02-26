locals {
  maas_all_machines = concat(
    [for vm in module.maas_compute : { id = vm.system_id, roles = vm.roles }],
    [{ id = module.maas_juju_controller.system_id, roles = module.maas_juju_controller.roles }],
    [{ id = module.maas_sunbeam.system_id, roles = module.maas_sunbeam.roles }],
  )
  maas_role_to_machines = {
    for role in distinct(flatten([for m in local.maas_all_machines : m.roles])) : role => [
      for m in local.maas_all_machines : m.id if contains(m.roles, role)
    ]
  }
}

resource "maas_vm_host" "lxd" {
  type          = "lxd"
  power_address = var.lxd_host_address
  certificate   = trimspace(file(var.maas_lxd_client_certificate_file))
  key           = trimspace(file(var.maas_lxd_client_key_file))
  name          = "lxd-host"
}

module "maas_juju_controller" {
  depends_on = [maas_vm_host.lxd]
  source     = "../modules/maas_compute"

  hostname               = "juju-controller"
  management_domain      = var.management_domain
  management_subnet_cidr = "10.10.10.0/24"
  management_ip          = cidrhost("10.10.10.0/24", 11)
  vm_host                = maas_vm_host.lxd.id

  cores           = "2"
  memory          = "4GiB"
  root_disk_size  = "40GiB"
  nb_osd          = 0
  osd_disk_size   = "50GiB"
  roles           = ["juju-controller"]
  isolation_cidrs = []
}

module "maas_sunbeam" {
  depends_on = [maas_vm_host.lxd]
  source     = "../modules/maas_compute"

  hostname               = "sunbeam"
  management_domain      = var.management_domain
  management_subnet_cidr = "10.10.10.0/24"
  management_ip          = cidrhost("10.10.10.0/24", 12)
  vm_host                = maas_vm_host.lxd.id

  cores           = "2"
  memory          = "4GiB"
  root_disk_size  = "40GiB"
  nb_osd          = 0
  osd_disk_size   = "50GiB"
  roles           = ["sunbeam"]
  isolation_cidrs = []
}

resource "maas_tag" "roles" {
  for_each = local.maas_role_to_machines
  name     = each.key
  machines = each.value
}
