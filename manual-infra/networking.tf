data "lxd_network" "main_bridge" {
  name = "lxdbr0"
}

locals {
  restricted_net                = "192.167.98.0/24"
  restricted_domain             = "res"
  restricted_allowed_dhcp_range = [3, 229]
  nb_compute_networks           = 3
  compute_nets = [
    for i in range(local.nb_compute_networks) : "10.20.${30 + i * 10}.0/24"
  ]
}

resource "lxd_network" "restricted" {
  name = "restrictedbr0"

  config = {
    "ipv4.address" = "${cidrhost(local.restricted_net, 1)}/24"
    "ipv4.nat"     = "true"
    "ipv4.dhcp"    = "true"
    "ipv4.dhcp.ranges" : "${cidrhost(local.restricted_net, local.restricted_allowed_dhcp_range[0])}-${cidrhost(local.restricted_net, local.restricted_allowed_dhcp_range[1])}"
    "ipv6.address" = "none"
    "ipv6.dhcp"    = "false"
    "dns.domain"   = local.restricted_domain
    "dns.mode"     = "none"
    "raw.dnsmasq"  = <<EOF
      server=${local.restricted_dns_ip}
    EOF
  }
}

resource "lxd_network" "computes" {
  count = local.nb_compute_networks
  name  = "computebr${count.index + 1}0"

  config = {
    "ipv4.address" = "${cidrhost(local.compute_nets[count.index], 1)}/24"
    "ipv4.nat"     = "true"
    "ipv4.dhcp"    = "false"
    "ipv6.address" = "none"
  }
}

resource "lxd_network_acl" "restricted" {
  name = "restricted"

  egress = [
    {
      description = "Allow communication to local network"
      action      = "allow"
      destination = local.restricted_net
      state       = "enabled"
    },
    {
      description = "Prevent external communication"
      action      = "reject"
      destination = "0.0.0.0"
      state       = "enabled"
    },
  ]

  ingress = [
    {
      description = "Allow communication from local network"
      action      = "allow"
      destination = local.restricted_net
      state       = "enabled"
    },
  ]
}
