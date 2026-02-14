# Test configuration to verify the structure works

variable "nb_vm" {
  default = 2
}

variable "vm_config" {
  default = {
    cores          = "4"
    memory         = "10GiB"
    root_disk_size = "75GiB"
    nb_osd         = 3
    osd_disk_size  = "50GiB"
    compute_nets   = []
  }
}

variable "vm_config_override" {
  default = {
    vm0 = {
      cores          = "8"
      memory         = "32GiB"
      root_disk_size = "100GiB"
      nb_osd         = 4
      osd_disk_size  = "100GiB"
      compute_nets   = ["compute_public"]
    }
    vm1 = {
      cores          = "6"
      memory         = "20GiB"
      root_disk_size = "75GiB"
      nb_osd         = 3
      osd_disk_size  = "50GiB"
      compute_nets   = ["compute_internal"]
    }
  }
}

output "test_output" {
  value = {
    vm0_cores = lookup(var.vm_config_override["vm0"], "cores", "4")
    vm0_memory = lookup(var.vm_config_override["vm0"], "memory", "10GiB")
    vm0_root_disk_size = lookup(var.vm_config_override["vm0"], "root_disk_size", "75GiB")
    vm0_nb_osd = lookup(var.vm_config_override["vm0"], "nb_osd", 3)
    vm0_osd_disk_size = lookup(var.vm_config_override["vm0"], "osd_disk_size", "50GiB")
    vm0_compute_nets = lookup(var.vm_config_override["vm0"], "compute_nets", [])

    vm1_cores = lookup(var.vm_config_override["vm1"], "cores", "4")
    vm1_memory = lookup(var.vm_config_override["vm1"], "memory", "10GiB")
    vm1_root_disk_size = lookup(var.vm_config_override["vm1"], "root_disk_size", "75GiB")
    vm1_nb_osd = lookup(var.vm_config_override["vm1"], "nb_osd", 3)
    vm1_osd_disk_size = lookup(var.vm_config_override["vm1"], "osd_disk_size", "50GiB")
    vm1_compute_nets = lookup(var.vm_config_override["vm1"], "compute_nets", [])
  }
}
