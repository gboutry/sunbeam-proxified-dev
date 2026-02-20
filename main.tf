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
    null = {
      source  = "hashicorp/null"
      version = ">=3.2.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">=4.0.0"
    }
  }
}

provider "cloudinit" {}
provider "null" {}
provider "tls" {}

provider "lxd" {
  generate_client_certificates = true
  accept_remote_certificate    = true
  remote {
    name    = "lxd_remote"
    default = true
    address = var.lxd_host_address
  }
}

resource "tls_private_key" "global" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "ssh_private_key" {
  content         = tls_private_key.global.private_key_pem
  filename        = "ssh_private_key"
  file_permission = "0600"
}

resource "local_file" "ssh_public_key" {
  content  = tls_private_key.global.public_key_openssh
  filename = "ssh_public_key.pub"
}

locals {
  manual_testbed_content = <<-EOT
deployment:
  provider: manual
  channel: 2024.1/edge
  topology: multi-node
  manifest: /home/ubuntu/manifest.yaml
machines:
%{for vm in local.computed_nodes~}
  - hostname: ${vm.hostname}
    ip: ${vm.ip}
    fqdn: ${vm.fqdn}
    osd-devices: ${join(",", vm.osd_devices)}
    roles: ${jsonencode(vm.roles)}
    external-networks:
      external: ${vm.management_net}
%{endfor~}
ssh:
  user: ubuntu
  private_key: ${abspath(local_sensitive_file.ssh_private_key.filename)}
  public_key: ${abspath(local_file.ssh_public_key.filename)}
EOT

  maas_testbed_content = <<-EOT
deployment:
  provider: maas
  channel: 2024.1/edge
  topology: multi-node
  manifest: /home/ubuntu/manifest.yaml
lxd-host:
  address: ${var.lxd_host_address}
spaces:
  management: management
%{for net_type, net_cfg in local.maas_network_configs~}
  ${net_type}: ${net_type}
%{endfor~}
machines:
%{for vm in concat(module.maas_juju_controller, module.maas_sunbeam)~}
  - hostname: ${vm.hostname}
    ip: ${vm.ip}
    fqdn: ${vm.fqdn}
    roles: ${jsonencode(vm.roles)}
%{endfor~}
%{for vm in local.computed_nodes~}
  - hostname: ${vm.hostname}
    ip: ${vm.ip}
    fqdn: ${vm.fqdn}
    osd-devices: ${join(",", vm.osd_devices)}
    roles: ${jsonencode(vm.roles)}
%{endfor~}
ssh:
  user: ubuntu
  private_key: ${abspath(local_sensitive_file.ssh_private_key.filename)}
  public_key: ${abspath(local_file.ssh_public_key.filename)}
EOT
}

resource "local_file" "testbed_yaml" {
  content  = var.enable_maas ? local.maas_testbed_content : local.manual_testbed_content
  filename = "testbed.yaml"
}
