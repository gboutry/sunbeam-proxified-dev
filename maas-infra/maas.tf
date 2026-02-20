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
  password      = var.lxd_trust_password
  name          = "lxd-host"
}

module "maas_juju_controller" {
  depends_on = [maas_vm_host.lxd]
  source     = "../modules/maas_compute"

  hostname          = "juju-controller"
  management_domain = var.management_domain
  vm_host           = maas_vm_host.lxd.id

  cores          = "2"
  memory         = "4GiB"
  root_disk_size = "40GiB"
  nb_osd         = 0
  osd_disk_size  = "50GiB"
  roles          = ["juju-controller"]
}

module "maas_sunbeam" {
  depends_on = [maas_vm_host.lxd]
  source     = "../modules/maas_compute"

  hostname          = "sunbeam"
  management_domain = var.management_domain
  vm_host           = maas_vm_host.lxd.id

  cores          = "2"
  memory         = "4GiB"
  root_disk_size = "40GiB"
  nb_osd         = 0
  osd_disk_size  = "50GiB"
  roles          = ["sunbeam"]
}

resource "maas_tag" "roles" {
  for_each = local.maas_role_to_machines
  name     = each.key
  machines = each.value
}
