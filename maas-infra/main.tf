terraform {
  required_providers {
    lxd = {
      source  = "terraform-lxd/lxd"
      version = ">=3.0.0"
    }
    maas = {
      source  = "canonical/maas"
      version = "~>2.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">=4.0.0"
    }
  }
}

provider "tls" {}

provider "lxd" {
  default_remote = "lxd_remote"

  remote {
    name    = "lxd_remote"
    address = var.lxd_provider_address != "" ? var.lxd_provider_address : var.lxd_host_address
  }
}

provider "maas" {
  api_version = "2.0"
  api_key     = var.maas_api_key
  api_url     = var.maas_api_url
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
  manifest_content = templatefile("${path.root}/templates/manifest.yaml", {
    management_cidr = var.maas_network_cidrs.internal,
    nameservers     = cidrhost(var.maas_network_cidrs.internal, 1),
  })

  testbed_content = <<-EOT
deployment:
  provider: maas
  channel: 2024.1/edge
  topology: multi-node
  manifest-is-overlay: true
  manifest: ${abspath(local_file.manifest_yaml.filename)}
maas:
  name: ${var.deployment_name}
  endpoint: ${jsonencode(var.maas_api_url)}
  api_key: ${jsonencode(var.maas_api_key)}
  network_spaces:
    management: management
    public: public
    data: data
    storage: storage
    storage-cluster: storage-cluster
    internal: internal
machines:
%{for vm in [module.maas_juju_controller, module.maas_sunbeam]~}
  - hostname: ${vm.hostname}
    ip: ${vm.ip}
    fqdn: ${vm.fqdn}
    roles: ${jsonencode(vm.roles)}
    external-networks:
      external: management
%{endfor~}
%{for vm in local.computed_nodes~}
  - hostname: ${vm.hostname}
    ip: ${vm.ip}
    fqdn: ${vm.fqdn}
    osd-devices: ${join(",", vm.osd_devices)}
    roles: ${jsonencode(vm.roles)}
    external-networks:
      external: management
%{endfor~}
ssh:
  user: ubuntu
  private_key: ${abspath(local_sensitive_file.ssh_private_key.filename)}
  public_key: ${abspath(local_file.ssh_public_key.filename)}
EOT
}

resource "local_file" "manifest_yaml" {
  content  = local.manifest_content
  filename = "${path.root}/manifest.yaml"
}

resource "local_file" "testbed_yaml" {
  content  = local.testbed_content
  filename = "testbed.yaml"
}
