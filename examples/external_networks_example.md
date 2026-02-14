# External Networks Configuration Test

This example demonstrates how the external-networks configuration works based on VM network attachments.

## Scenario Setup

```hcl
variable "nb_vm" {
  default = 4
}

variable "vm_config" {
  default = {
    # vm0: Control plane - management only (no compute networks)
    vm0 = {
      cores        = "6"
      memory       = "20GiB"
      compute_nets = []  # No external network interfaces
    }
    
    # vm1: Compute node on first network only
    vm1 = {
      cores        = "8"
      memory       = "16GiB"
      compute_nets = ["computebr10"]  # Only physnet1
    }
    
    # vm2: Compute node on second and third networks
    vm2 = {
      cores        = "8"
      memory       = "16GiB"
      compute_nets = ["computebr20", "computebr30"]  # physnet2 and physnet3
    }
    
    # vm3: Networking node on all compute networks
    vm3 = {
      cores        = "8"
      memory       = "16GiB"
      compute_nets = ["computebr10", "computebr20", "computebr30"]  # All physnets
    }
  }
}
```

## Resulting Manifest External Networks

The manifest.yaml will generate:

```yaml
external-networks:
  physnet1:  # computebr10 (10.20.30.0/24)
    cidr: 10.20.30.0/24
    gateway: 10.20.30.1
    range: 10.20.30.2-10.20.30.254
    network_type: flat
    nics:
      bm1.res: enp6s0   # First compute net for vm1
      bm3.res: enp6s0   # First compute net for vm3
  
  physnet2:  # computebr20 (10.20.40.0/24)
    cidr: 10.20.40.0/24
    gateway: 10.20.40.1
    range: 10.20.40.2-10.20.40.254
    network_type: flat
    nics:
      bm2.res: enp6s0   # First compute net for vm2
      bm3.res: enp7s0   # Second compute net for vm3
  
  physnet3:  # computebr30 (10.20.50.0/24)
    cidr: 10.20.50.0/24
    gateway: 10.20.50.1
    range: 10.20.50.2-10.20.50.254
    network_type: flat
    nics:
      bm2.res: enp7s0   # Second compute net for vm2
      bm3.res: enp8s0   # Third compute net for vm3
```

## Key Points

1. **vm0 (bm0.res)** doesn't appear in any nics section because it has no compute networks
2. **vm1 (bm1.res)** only appears in physnet1 with enp6s0 (its first and only compute network)
3. **vm2 (bm2.res)** appears in physnet2 and physnet3:
   - computebr20 is its first compute net → enp6s0
   - computebr30 is its second compute net → enp7s0
4. **vm3 (bm3.res)** appears in all physnets:
   - computebr10 is its first compute net → enp6s0
   - computebr20 is its second compute net → enp7s0
   - computebr30 is its third compute net → enp8s0

## Interface Naming Logic

All VMs have:
- **enp5s0** (eth0): Management network (restrictedbr0) - always present

Compute network interfaces are assigned based on order in the `compute_nets` list:
- **enp6s0** (eth1): First network in compute_nets
- **enp7s0** (eth2): Second network in compute_nets
- **enp8s0** (eth3): Third network in compute_nets

**Important**: The interface name depends on the ORDER in each VM's `compute_nets`, not on which physical network it is!

Example:
- VM with `compute_nets = ["computebr20", "computebr10"]` has computebr20 on enp6s0 and computebr10 on enp7s0
- VM with `compute_nets = ["computebr10", "computebr20"]` has computebr10 on enp6s0 and computebr20 on enp7s0
