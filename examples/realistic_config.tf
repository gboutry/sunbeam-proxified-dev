# Realistic configuration example using actual network names from networking.tf
# This demonstrates how to configure VMs with different compute network attachments

# Example 1: Mixed compute network attachments
# - vm0: Connected only to management (no compute networks)
# - vm1: Connected to first compute network
# - vm2: Connected to all compute networks

variable "nb_vm" {
  default = 3
}

variable "use_proxy" {
  default = false
}

variable "vm_config" {
  default = {
    cores          = "6"
    memory         = "20GiB"
    root_disk_size = "100GiB"
    nb_osd         = 4
    osd_disk_size  = "100GiB"
    compute_nets   = []
  }
}

variable "vm_config_override" {
  default = {
    # vm0: Management-only node (no compute networks)
    # Perfect for control plane or storage-only nodes
    vm0 = {
      compute_nets = []  # Only connected to restrictedbr0 (management)
    }

    # vm1: Single compute network
    # Good for dedicated workload isolation
    vm1 = {
      cores          = "6"
      memory         = "20GiB"
      root_disk_size = "75GiB"
      nb_osd         = 3
      osd_disk_size  = "50GiB"
      compute_nets   = ["computebr10"]  # Connected to restrictedbr0 + computebr10
    }

    # vm2: Multiple compute networks
    # Useful for networking nodes or multi-tenant scenarios
    vm2 = {
      cores          = "8"
      memory         = "24GiB"
      root_disk_size = "75GiB"
      nb_osd         = 3
      osd_disk_size  = "50GiB"
      compute_nets   = ["computebr10", "computebr20", "computebr30"]  # All compute networks
    }
  }
}

# Note: All VMs are ALWAYS connected to restrictedbr0 (management network) as eth0
# The compute_nets parameter only controls ADDITIONAL network connections (eth1, eth2, etc.)
#
# Available compute networks (from networking.tf):
# - computebr10: 10.20.30.0/24
# - computebr20: 10.20.40.0/24  
# - computebr30: 10.20.50.0/24
