
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
      # For each host, if it has this network, determine the interface name
      # Interface name is enp{5+position+1}s0 where position is the index in that host's compute_nets list
      nics = {
        for vm in module.compute : vm.fqdn => "enp${5 + index(vm.compute_nets, lxd_network.computes[idx].name) + 1}s0"
        if contains(vm.compute_nets, lxd_network.computes[idx].name)
      }
    }
  }
}

module "compute" {
  depends_on = [null_resource.proxy]
  source     = "./modules/compute"
  count      = var.nb_vm

  # Start with vm_config defaults, then override with vm_config_override for this VM
  cores          = try(var.vm_config_override["vm${count.index}"].cores, var.vm_config.cores)
  memory         = try(var.vm_config_override["vm${count.index}"].memory, var.vm_config.memory)
  root_disk_size = try(var.vm_config_override["vm${count.index}"].root_disk_size, var.vm_config.root_disk_size)
  nb_osd         = try(var.vm_config_override["vm${count.index}"].nb_osd, var.vm_config.nb_osd)
  osd_disk_size  = try(var.vm_config_override["vm${count.index}"].osd_disk_size, var.vm_config.osd_disk_size)
  compute_nets   = try(var.vm_config_override["vm${count.index}"].compute_nets, var.vm_config.compute_nets)

  hostname          = "bm${count.index}"
  management_domain = local.restricted_domain
  management_net    = lxd_network.restricted.name
  management_dns    = local.nameserver
  proxy_url         = local.proxy_url
  proxy_ip          = local.proxy_ip
  no_proxy          = local.no_proxy
  use_proxy         = var.use_proxy
}

resource "lxd_instance_file" "manifest" {
  depends_on = [module.compute]
  instance   = module.compute[0].name
  content = templatefile("${path.root}/templates/compute/manifest.yaml", {
    use_proxy          = var.use_proxy,
    proxy_url          = local.proxy_url,
    no_proxy           = local.no_proxy,
    restricted_network = local.restricted_net,
    restricted_domain  = local.restricted_domain,
    loadbalancer       = local.loadbalancer,
    nameservers        = local.nameserver
    external_networks  = local.external_networks
    osds               = { for compute in module.compute : compute.fqdn => join(",", formatlist("/dev/disk/by-id/scsi-SQEMU_QEMU_HARDDISK_lxd_%s", compute.osds)) }
  })
  target_path = "/home/ubuntu/manifest.yaml"
  mode        = "0644"
  uid         = 1000
  gid         = 1000

}
