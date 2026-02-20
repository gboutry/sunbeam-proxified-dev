locals {
  maas_network_configs = {
    internal = {
      cidr   = var.maas_network_cidrs.internal
      bridge = "internal"
    }
    public = {
      cidr   = var.maas_network_cidrs.public
      bridge = "public"
    }
    data = {
      cidr   = var.maas_network_cidrs.data
      bridge = "data"
    }
    storage = {
      cidr   = var.maas_network_cidrs.storage
      bridge = "storage"
    }
    "storage-cluster" = {
      cidr   = var.maas_network_cidrs.storage_cluster
      bridge = "storagecluster"
    }
  }
}

resource "lxd_network" "maas_networks" {
  for_each = local.maas_network_configs

  name = each.value.bridge

  config = {
    "ipv4.address" = "${cidrhost(each.value.cidr, 1)}/24"
    "ipv4.nat"     = "true"
    "ipv4.dhcp"    = "false"
    "ipv6.address" = "none"
  }
}
