locals {
  no_proxy     = "localhost,127.0.0.1,.local,${local.restricted_domain},${local.restricted_net},${join(",", local.compute_nets)}"
  loadbalancer = "${cidrhost(local.restricted_net, local.restricted_allowed_dhcp_range[1] + 1)}-${cidrhost(local.restricted_net, -2)}"
  nameserver   = cidrhost(local.restricted_net, 1)

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

module "manual_compute" {
  count      = var.nb_vm
  depends_on = [null_resource.proxy, lxd_instance.proxy, lxd_network.restricted, lxd_network.computes]
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
  proxy_url         = local.proxy_url
  proxy_ip          = local.proxy_ip
  no_proxy          = local.no_proxy
  use_proxy         = var.use_proxy
  ssh_public_key    = trimspace(tls_private_key.global.public_key_openssh)
}

resource "lxd_instance_file" "manifest" {
  depends_on = [module.manual_compute]
  instance   = module.manual_compute[0].name
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
  target_path = "/home/ubuntu/manifest.yaml"
  mode        = "0644"
  uid         = 1000
  gid         = 1000
}
