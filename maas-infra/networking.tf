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

  # Reserve API endpoint pools on internal/public networks (10 IPs each).
  maas_api_reserved_ranges = {
    internal = {
      subnet  = var.maas_network_cidrs.internal
      start   = cidrhost(var.maas_network_cidrs.internal, 71)
      end     = cidrhost(var.maas_network_cidrs.internal, 80)
      comment = "${var.deployment_name}-internal-api"
    }
    public = {
      subnet  = var.maas_network_cidrs.public
      start   = cidrhost(var.maas_network_cidrs.public, 71)
      end     = cidrhost(var.maas_network_cidrs.public, 80)
      comment = "${var.deployment_name}-public-api"
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
    "dns.mode"     = "none"
    "ipv6.address" = "none"
  }
}

# Create one MAAS space per OpenStack network type.
# VLAN-to-space assignment is handled by bootstrap.sh after MAAS discovers
# the bridges (MAAS discovery takes ~60s, making data-source lookups unreliable
# within the same apply that creates the bridges).
resource "maas_space" "openstack" {
  for_each = local.maas_network_configs
  name     = each.key
}

resource "maas_subnet_ip_range" "openstack_api" {
  for_each = local.maas_api_reserved_ranges

  subnet   = each.value.subnet
  type     = "reserved"
  start_ip = each.value.start
  end_ip   = each.value.end
  comment  = each.value.comment

  depends_on = [maas_vm_host.lxd]
}
