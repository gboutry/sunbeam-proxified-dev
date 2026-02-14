# Example configuration showing how to use the vm_config variable
# This file can be used as a reference for configuring your VMs

# Example 1: Simple override of cores and memory
vm_config_simple = {
  vm0 = {
    cores  = "8"
    memory = "32GiB"
  }
  vm1 = {
    cores  = "6"
    memory = "20GiB"
  }
}

# Example 2: Full configuration with all parameters
vm_config_complex = {
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
  vm2 = {
    cores          = "4"
    memory         = "10GiB"
    root_disk_size = "50GiB"
    nb_osd         = 2
    osd_disk_size  = "50GiB"
    compute_nets   = ["compute_private"]
  }
}

# Example 3: Minimal configuration - just specify what you want to override
vm_config_minimal = {
  vm0 = {
    cores = "6"
    # memory will use default (20GiB for vm0)
  }
  vm1 = {
    memory = "15GiB"
    # cores will use default (4 for vm1)
  }
}

# Example 4: Homogeneous configuration - all VMs have same spec
vm_config_homogeneous = {
  vm0 = {
    cores          = "6"
    memory         = "20GiB"
    root_disk_size = "75GiB"
    nb_osd         = 3
    osd_disk_size  = "50GiB"
    compute_nets   = ["compute_public", "compute_internal"]
  }
  vm1 = {
    cores          = "6"
    memory         = "20GiB"
    root_disk_size = "75GiB"
    nb_osd         = 3
    osd_disk_size  = "50GiB"
    compute_nets   = ["compute_public", "compute_internal"]
  }
}

# Example 5: Configuration with specific disk sizes
vm_config_disks = {
  vm0 = {
    cores          = "4"
    memory         = "16GiB"
    root_disk_size = "200GiB"
    nb_osd         = 6
    osd_disk_size  = "200GiB"
    compute_nets   = []
  }
}

# Example 6: Configuration with no OSD disks
vm_config_no_osd = {
  vm0 = {
    cores          = "2"
    memory         = "4GiB"
    root_disk_size = "20GiB"
    nb_osd         = 0
    compute_nets   = ["compute_public"]
  }
}

# Example 7: Configuration specifying network attachments
vm_config_networks = {
  vm0 = {
    cores          = "8"
    memory         = "32GiB"
    compute_nets   = ["compute_public"]
  }
  vm1 = {
    cores          = "8"
    memory         = "32GiB"
    compute_nets   = ["compute_private"]
  }
  vm2 = {
    cores          = "4"
    memory         = "16GiB"
    compute_nets   = ["compute_public", "compute_private"]
  }
}
