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
  for_each = var.enable_maas ? local.maas_network_configs : {}

  name = each.value.bridge

  config = {
    "ipv4.address" = "${cidrhost(each.value.cidr, 1)}/24"
    "ipv4.nat"     = "true"
    "ipv4.dhcp"    = "false"
    "ipv6.address" = "none"
  }
}

module "maas_juju_controller" {
  count      = var.enable_maas ? 1 : 0
  depends_on = [null_resource.proxy, lxd_instance.proxy, lxd_network.restricted]
  source     = "./modules/compute"

  hostname          = "juju-controller"
  management_domain = local.restricted_domain
  management_net    = lxd_network.restricted.name
  management_dns    = local.nameserver
  proxy_url         = local.proxy_url
  proxy_ip          = local.proxy_ip
  no_proxy          = local.no_proxy
  use_proxy         = var.use_proxy
  ssh_public_key    = trimspace(tls_private_key.global.public_key_openssh)

  cores          = "2"
  memory         = "4GiB"
  root_disk_size = "40GiB"
  nb_osd         = 0
  osd_disk_size  = "50GiB"
  compute_nets   = []
  roles          = ["juju-controller"]
}

module "maas_sunbeam" {
  count      = var.enable_maas ? 1 : 0
  depends_on = [null_resource.proxy, lxd_instance.proxy, lxd_network.restricted]
  source     = "./modules/compute"

  hostname          = "sunbeam"
  management_domain = local.restricted_domain
  management_net    = lxd_network.restricted.name
  management_dns    = local.nameserver
  proxy_url         = local.proxy_url
  proxy_ip          = local.proxy_ip
  no_proxy          = local.no_proxy
  use_proxy         = var.use_proxy
  ssh_public_key    = trimspace(tls_private_key.global.public_key_openssh)

  cores          = "2"
  memory         = "4GiB"
  root_disk_size = "40GiB"
  nb_osd         = 0
  osd_disk_size  = "50GiB"
  compute_nets   = []
  roles          = ["sunbeam"]
}
