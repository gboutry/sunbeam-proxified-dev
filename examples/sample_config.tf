# Sample terraform configuration demonstrating the vm_config usage
# This can be used to test the configuration

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

provider "lxd" {
  generate_client_certificates = true
}

# Example configuration with 3 VMs
variable "nb_vm" {
  default = 3
}

variable "use_proxy" {
  default = false
}

variable "vm_config" {
  type = map(object({
    cores          = optional(string)
    memory         = optional(string)
    root_disk_size = optional(string)
    nb_osd         = optional(number)
    osd_disk_size  = optional(string)
    compute_nets   = optional(list(string))
  }))
  default = {
    # vm0: High-capacity storage node
    vm0 = {
      cores          = "8"
      memory         = "32 GiB"
      root_disk_size = "100 GiB"
      nb_osd         = 4
      osd_disk_size  = "100 GiB"
      compute_nets   = []
    }
    # vm1: General compute node
    vm1 = {
      cores          = "6"
      memory         = "20 GiB"
      root_disk_size = "75 GiB"
      nb_osd         = 3
      osd_disk_size  = "50 GiB"
      compute_nets   = []
    }
    # vm2: Minimal node
    vm2 = {
      cores          = "4"
      memory         = "10 GiB"
      root_disk_size = "50 GiB"
      nb_osd         = 2
      osd_disk_size  = "30 GiB"
      compute_nets   = []
    }
  }
}

module "compute" {
  source   = "./modules/compute"
  count    = var.nb_vm

  cores          = lookup(var.vm_config["vm${count.index}"], "cores", count.index == 0 ? "6" : "4")
  memory         = lookup(var.vm_config["vm${count.index}"], "memory", count.index == 0 ? "20 GiB" : "10 GiB")
  root_disk_size = lookup(var.vm_config["vm${count.index}"], "root_disk_size", "75 GiB")
  nb_osd         = lookup(var.vm_config["vm${count.index}"], "nb_osd", 3)
  osd_disk_size  = lookup(var.vm_config["vm${count.index}"], "osd_disk_size", "50 GiB")

  hostname        = "bm${count.index}"
  management_domain = "example.com"
  management_net  = "restricted"
  management_dns  = "10.101.0.1"
  compute_nets    = lookup(var.vm_config["vm${count.index}"], "compute_nets", [])
  proxy_url       = "http://10.101.0.2:3128"
  proxy_ip        = "10.101.0.2"
  no_proxy        = "localhost,127.0.0.1"
  use_proxy       = var.use_proxy
}

output "vm_configs" {
  value = [
    for i, vm in module.compute : {
      name            = vm.name
      fqdn            = vm.fqdn
      hostname        = vm.hostname
      cores           = vm.cores
      memory          = vm.memory
      root_disk_size  = vm.root_disk_size
      nb_osd          = vm.nb_osd
      osd_disk_size   = vm.osd_disk_size
      compute_nets    = vm.compute_nets
    }
  ]
}
