locals {
  no_proxy            = "localhost,127.0.0.1,.local,${local.restricted_domain},${local.restricted_net},${join(",", local.compute_nets)}"
  loadbalancer        = "${cidrhost(local.restricted_net, local.restricted_allowed_dhcp_range[1] + 1)}-${cidrhost(local.restricted_net, -2)}"
  restricted_dns_ip   = cidrhost(local.restricted_net, 2)
  restricted_proxy_ip = cidrhost(local.restricted_net, 3)
  nameserver          = local.restricted_dns_ip
  compute_management_ips = [
    for i in range(var.nb_vm) : cidrhost(local.restricted_net, 10 + i)
  ]
  dns_host_records = concat(
    [
      "host-record=public.sunbeam.${local.restricted_domain},${cidrhost(local.restricted_net, local.restricted_allowed_dhcp_range[1] + 4)}",
      "host-record=internal.sunbeam.${local.restricted_domain},${cidrhost(local.restricted_net, local.restricted_allowed_dhcp_range[1] + 5)}",
      "host-record=s3.sunbeam.${local.restricted_domain},${cidrhost(local.restricted_net, local.restricted_allowed_dhcp_range[1] + 6)}",
    ],
    [
      for i in range(var.nb_vm) : "host-record=bm${i},bm${i}.${local.restricted_domain},${local.compute_management_ips[i]}"
    ]
  )
  dnsmasq_config = templatefile("${path.root}/templates/dns/restrictedbr0.conf", {
    dns_forwarder = var.dns_forwarder,
    dns_ip        = local.restricted_dns_ip,
    host_records  = local.dns_host_records,
  })

  # Build external networks configuration for manifest
  # Maps each compute network to its details and which hosts have interfaces on it
  external_networks = {
    for idx, net_cidr in local.compute_nets : "physnet${idx + 1}" => {
      network_name = lxd_network.computes[idx].name
      cidr         = net_cidr
      gateway      = cidrhost(net_cidr, 1)
      range        = "${cidrhost(net_cidr, 2)}-${cidrhost(net_cidr, -2)}"
      # Interface name is enp{5+position+1}s0 where position is the index in that host's compute_nets list
      nics = {
        for vm in module.manual_compute : vm.fqdn => "enp${5 + index(vm.compute_nets, lxd_network.computes[idx].name) + 1}s0"
        if contains(vm.compute_nets, lxd_network.computes[idx].name)
      }
    }
  }

  vm_effective_isolation_nets = [
    for i in range(var.nb_vm) : (
      try(var.vm_config_override["vm${i}"].isolation_nets, null) != null
      ? try(var.vm_config_override["vm${i}"].isolation_nets, [])
      : (var.vm_config.isolation_nets != null ? var.vm_config.isolation_nets : [])
    )
  ]
}

data "cloudinit_config" "cloudinit-dns" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"

    content = templatefile("${path.root}/templates/dns/cloudinit.yaml", {
      dns_forwarder = var.dns_forwarder,
      dns_ip        = local.restricted_dns_ip,
    })
  }
}

resource "lxd_instance" "dns" {
  name  = "dns"
  image = "ubuntu:noble"

  limits = {
    cpu    = "1"
    memory = "1GiB"
  }

  config = {
    "user.access_interface" = "eth0"
    "user.user-data"        = data.cloudinit_config.cloudinit-dns.rendered
  }

  device {
    name = "eth0"
    type = "nic"
    properties = {
      name           = "enp5s0"
      network        = lxd_network.restricted.name
      "ipv4.address" = local.restricted_dns_ip
    }
  }

  provisioner "local-exec" {
    command     = "sleep 15 && lxc exec ${self.name} -- cloud-init status --wait >/dev/null"
    interpreter = ["bash", "-c"]
  }
}

resource "lxd_instance_file" "dnsmasq_config" {
  depends_on  = [lxd_instance.dns, module.manual_compute]
  instance    = lxd_instance.dns.name
  content     = local.dnsmasq_config
  target_path = "/etc/dnsmasq.d/restrictedbr0.conf"
  mode        = "0644"
  uid         = 0
  gid         = 0
}

resource "null_resource" "dns_reload" {
  depends_on = [lxd_instance_file.dnsmasq_config]

  triggers = {
    dnsmasq_config_sha = sha256(local.dnsmasq_config)
  }

  provisioner "local-exec" {
    command     = "lxc exec ${lxd_instance.dns.name} -- systemctl restart dnsmasq"
    interpreter = ["bash", "-c"]
  }
}

module "manual_compute" {
  count      = var.nb_vm
  depends_on = [null_resource.proxy, lxd_instance.proxy, lxd_instance.dns, lxd_network.restricted, lxd_network.computes]
  source     = "../modules/manual_compute"

  cores          = try(var.vm_config_override["vm${count.index}"].cores, var.vm_config.cores)
  memory         = try(var.vm_config_override["vm${count.index}"].memory, var.vm_config.memory)
  root_disk_size = try(var.vm_config_override["vm${count.index}"].root_disk_size, var.vm_config.root_disk_size)
  nb_osd         = try(var.vm_config_override["vm${count.index}"].nb_osd, var.vm_config.nb_osd)
  osd_disk_size  = try(var.vm_config_override["vm${count.index}"].osd_disk_size, var.vm_config.osd_disk_size)
  compute_nets   = try(var.vm_config_override["vm${count.index}"].compute_nets, var.vm_config.compute_nets)
  isolation_nets = local.vm_effective_isolation_nets[count.index]
  roles          = try(var.vm_config_override["vm${count.index}"].roles, var.vm_config.roles)

  hostname          = "bm${count.index}"
  management_domain = local.restricted_domain
  management_net    = lxd_network.restricted.name
  management_dns    = local.nameserver
  management_ip     = local.compute_management_ips[count.index]
  proxy_url         = local.proxy_url
  proxy_ip          = local.restricted_proxy_ip
  no_proxy          = local.no_proxy
  use_proxy         = var.use_proxy
  ssh_public_key    = trimspace(tls_private_key.global.public_key_openssh)
}

resource "local_file" "manifest_yaml" {
  content = templatefile("${path.root}/templates/compute/manifest.yaml", {
    use_proxy          = var.use_proxy,
    proxy_url          = local.proxy_url,
    no_proxy           = local.no_proxy,
    restricted_network = local.restricted_net,
    restricted_domain  = local.restricted_domain,
    loadbalancer       = local.loadbalancer,
    nameservers        = local.nameserver
    external_networks  = local.external_networks
    osds               = { for compute in module.manual_compute : compute.fqdn => join(",", formatlist("/dev/disk/by-id/scsi-SQEMU_QEMU_HARDDISK_lxd_%s", compute.osds)) }
  })
  filename = "${path.root}/manifest.yaml"
}
