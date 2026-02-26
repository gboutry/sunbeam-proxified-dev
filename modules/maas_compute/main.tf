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

  # Keep one management NIC on a DHCP-enabled subnet for MAAS composition.
  network_interfaces {
    name        = "eth0"
    subnet_cidr = var.management_subnet_cidr
    ip_address  = var.management_ip != "" ? var.management_ip : null
  }

  # Isolation NICs start at eth1, one per OpenStack network the VM participates in.
  dynamic "network_interfaces" {
    for_each = var.isolation_cidrs
    content {
      name        = "eth${network_interfaces.key + 1}"
      subnet_cidr = network_interfaces.value
    }
  }
}
