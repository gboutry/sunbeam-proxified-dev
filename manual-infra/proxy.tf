locals {
  proxy_url      = var.use_proxy ? "http://${lxd_instance.proxy[0].name}.${lxd_network.restricted.config["dns.domain"]}:3128" : ""
  main_bridge_ip = cidrhost(data.lxd_network.main_bridge.config["ipv4.address"], 2)
  proxy_ip       = var.use_proxy ? cidrhost(lxd_network.restricted.config["ipv4.address"], 2) : ""
}

data "cloudinit_config" "cloudinit-proxy" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"

    content = templatefile("${path.root}/templates/proxy/cloudinit.yaml", {
      main_bridge_ip     = local.main_bridge_ip,
      restricted_network = local.restricted_net,
    })
  }
}

resource "lxd_instance" "proxy" {
  count = var.use_proxy ? 1 : 0
  name  = "squid"
  image = "ubuntu:noble"

  limits = {
    cpu    = "2"
    memory = "2GiB"
  }

  config = {
    "user.access_interface" = "eth0"
    "user.user-data"        = data.cloudinit_config.cloudinit-proxy.rendered
    "user.network-config"   = file("${path.root}/templates/proxy/network.yaml")
  }

  device {
    name = "eth0"
    type = "nic"
    properties = {
      name           = "enp5s0"
      network        = data.lxd_network.main_bridge.name
      "ipv4.address" = local.main_bridge_ip
    }
  }

  device {
    name = "eth1"
    type = "nic"
    properties = {
      name           = "enp6s0"
      network        = lxd_network.restricted.name
      "ipv4.address" = local.proxy_ip
    }
  }

  provisioner "local-exec" {
    command     = "sleep 15 && lxc exec ${self.name} -- cloud-init status --wait >/dev/null"
    interpreter = ["bash", "-c"]
  }
}

resource "lxd_instance_file" "allowed_domains" {
  count       = var.use_proxy ? 1 : 0
  instance    = lxd_instance.proxy[0].name
  content     = file("${path.root}/templates/proxy/allowed_domains.txt")
  target_path = "/etc/squid/allowed_domains.txt"
  mode        = "0644"
  uid         = 0
  gid         = 0
}

resource "lxd_instance_file" "squid_conf_block" {
  count      = var.use_proxy ? 1 : 0
  depends_on = [lxd_instance_file.allowed_domains]
  instance   = lxd_instance.proxy[0].name
  content = templatefile("${path.root}/templates/proxy/squid.conf", {
    localnet = local.restricted_net
  })
  target_path = "/etc/squid/squid.conf"
  mode        = "0644"
  uid         = 0
  gid         = 0

  provisioner "local-exec" {
    command     = "lxc exec ${lxd_instance.proxy[0].name} -- squid -k reconfigure"
    interpreter = ["bash", "-c"]
  }

  lifecycle {
    replace_triggered_by = [
      lxd_instance_file.allowed_domains
    ]
  }
}

resource "null_resource" "proxy" {
  count      = var.use_proxy ? 1 : 0
  depends_on = [lxd_instance.proxy, lxd_instance_file.squid_conf_block, lxd_instance_file.allowed_domains]
}
