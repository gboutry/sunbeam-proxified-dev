module "maas_compute" {
  count      = var.nb_vm
  depends_on = [maas_vm_host.lxd]
  source     = "../modules/maas_compute"

  hostname          = "bm${count.index}"
  management_domain = var.management_domain
  vm_host           = maas_vm_host.lxd.id
  cores          = try(var.vm_config_override["vm${count.index}"].cores, var.vm_config.cores)
  memory         = try(var.vm_config_override["vm${count.index}"].memory, var.vm_config.memory)
  root_disk_size = try(var.vm_config_override["vm${count.index}"].root_disk_size, var.vm_config.root_disk_size)
  nb_osd         = try(var.vm_config_override["vm${count.index}"].nb_osd, var.vm_config.nb_osd)
  osd_disk_size  = try(var.vm_config_override["vm${count.index}"].osd_disk_size, var.vm_config.osd_disk_size)
  roles          = try(var.vm_config_override["vm${count.index}"].roles, var.vm_config.roles)
}
