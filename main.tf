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
}

resource "tls_private_key" "global" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "ssh_private_key" {
  content         = tls_private_key.global.private_key_pem
  filename        = "ssh_private_key"
  file_permission = "0600"
}

resource "local_sensitive_file" "ssh_public_key" {
  content  = tls_private_key.global.public_key_openssh
  filename = "ssh_public_key.pub"
}

resource "local_file" "testbed_yaml" {
  content  = <<-EOT
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
    external-networks:
      external: ${vm.management_net}
%{endfor~}
EOT
  filename = "testbed.yaml"
}
