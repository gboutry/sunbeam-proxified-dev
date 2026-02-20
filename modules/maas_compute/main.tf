terraform {
  required_providers {
    maas = {
      source  = "canonical/maas"
      version = "~>2.0"
    }
  }
}

locals {
  fqdn         = "${var.hostname}.${var.management_domain}"
  memory_mb    = tonumber(trimspace(replace(replace(var.memory, "GiB", ""), "GB", ""))) * 1024
  root_disk_gb = tonumber(trimspace(replace(replace(var.root_disk_size, "GiB", ""), "GB", "")))
  osd_disk_gb  = tonumber(trimspace(replace(replace(var.osd_disk_size, "GiB", ""), "GB", "")))
}

resource "maas_vm_host_machine" "compute" {
  vm_host  = var.vm_host
  hostname = var.hostname
  cores    = tonumber(var.cores)
  memory   = local.memory_mb

  storage_disks { size_gigabytes = local.root_disk_gb }

  dynamic "storage_disks" {
    for_each = range(var.nb_osd)
    content { size_gigabytes = local.osd_disk_gb }
  }
}
