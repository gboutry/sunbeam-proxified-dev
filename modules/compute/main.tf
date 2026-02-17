terraform {
  required_providers {
    lxd = {
      source  = "terraform-lxd/lxd"
      version = ">=2.5.0"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = ">=2.3.6"
    }
  }
}

resource "lxd_volume" "osd" {
  count        = var.nb_osd
  name         = "${var.hostname}_osd${count.index}"
  pool         = "default"
  type         = "custom"
  content_type = "block"
  config = {
    size = var.osd_disk_size
  }
}

locals {
  fqdn = "${var.hostname}.${var.management_domain}"
}

data "cloudinit_config" "cloudinit-compute" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"

    content = var.use_proxy ? templatefile("${path.module}/templates/cloudinit-proxy.yaml", {
      hostname          = var.hostname,
      fqdn              = local.fqdn,
      proxy_url         = var.proxy_url,
      no_proxy          = var.no_proxy,
      management_domain = var.management_domain,
      ssh_public_key    = var.ssh_public_key,
      }) : templatefile("${path.module}/templates/cloudinit.yaml", {
      hostname          = var.hostname,
      fqdn              = local.fqdn,
      management_domain = var.management_domain,
      ssh_public_key    = var.ssh_public_key,
    })
  }
}

resource "lxd_instance" "compute" {
  name  = var.hostname
  image = "ubuntu:noble"
  type  = "virtual-machine"

  limits = {
    cpu    = var.cores
    memory = var.memory
  }

  config = {
    "user.access_interface" = "enp5s0"
    "user.user-data"        = data.cloudinit_config.cloudinit-compute.rendered
    "user.network-config" = var.use_proxy ? templatefile("${path.module}/templates/network-proxy.yaml", {
      proxy_ip       = var.proxy_ip
      nameservers    = jsonencode([var.management_dns])
      search_domains = jsonencode([var.management_domain])
      }) : templatefile("${path.module}/templates/network.yaml", {
      nameservers    = jsonencode([var.management_dns])
      search_domains = jsonencode([var.management_domain])
    })
  }

  device {
    name = "eth0"
    type = "nic"
    properties = {
      name    = "eth0"
      network = var.management_net
    }
  }

  dynamic "device" {
    for_each = var.compute_nets
    content {
      name = "eth${index(var.compute_nets, device.value) + 1}"
      type = "nic"
      properties = {
        name    = "eth${index(var.compute_nets, device.value) + 1}"
        network = device.value
      }
    }
  }

  device {
    name = "root"
    type = "disk"
    properties = {
      path = "/"
      pool = "default"
      size = var.root_disk_size
    }
  }

  dynamic "device" {
    for_each = lxd_volume.osd
    content {
      name = device.value.name

      type = "disk"

      properties = {
        pool   = "default"
        source = device.value.name
      }
    }
  }

  provisioner "local-exec" {
    command     = "sleep 15 && lxc exec ${self.name} -- cloud-init status --wait >/dev/null"
    interpreter = ["bash", "-c"]
  }
}
