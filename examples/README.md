# VM Configuration Guide

This guide explains how to configure VMs for Sunbeam deployments using the `vm_config` and `vm_config_override` variables.

## Network Architecture

All VMs in a Sunbeam deployment have:

1. **Management Network (always connected)**: Every VM is connected to `restrictedbr0` (192.167.98.0/24) as `eth0`. This is mandatory and automatic.

2. **Compute Networks (optional)**: VMs can be connected to 0 or more compute networks based on your requirements.

### Available Networks

From `networking.tf`, the following networks are created:

- **restrictedbr0**: 192.167.98.0/24 (management - always attached)
- **computebr10**: 10.20.30.0/24 (compute network 1)
- **computebr20**: 10.20.40.0/24 (compute network 2)
- **computebr30**: 10.20.50.0/24 (compute network 3)

## VM Configuration Variables

The system uses two variables for VM configuration:

### vm_config (default values for all VMs)

The `vm_config` variable provides default configuration values applied to all VMs:

```hcl
variable "vm_config" {
  type = object({
    cores          = string
    memory         = string
    root_disk_size = string
    nb_osd         = number
    osd_disk_size  = string
    compute_nets   = list(string)
  })
  default = {
    cores          = "4"
    memory         = "10GiB"
    root_disk_size = "75GiB"
    nb_osd         = 3
    osd_disk_size  = "50GiB"
    compute_nets   = []
  }
}
```

### vm_config_override (per-VM overrides)

The `vm_config_override` variable allows you to override specific VMs while inheriting defaults from `vm_config`:

```hcl
variable "vm_config_override" {
  type = map(object({
    cores          = optional(string)
    memory         = optional(string)
    root_disk_size = optional(string)
    nb_osd         = optional(number)
    osd_disk_size  = optional(string)
    compute_nets   = optional(list(string))
  }))
  default = {}
}
```

### Configuration Priority

When determining the final VM configuration, the system uses this priority:

1. **vm_config_override["vmN"]** - Override for specific VM (highest priority)
2. **vm_config** - Default values (fallback for all VMs)

### Defaults Summary

| Parameter | Default Value | Notes |
|-----------|---------------|-------|
| cores | "4" | CPU cores allocated |
| memory | "10GiB" | RAM allocated |
| root_disk_size | "75GiB" | Root filesystem size |
| nb_osd | 3 | Number of Ceph OSD disks |
| osd_disk_size | "50GiB" | Size per OSD disk |
| compute_nets | [] | No compute networks (management only) |

## Configuration Examples

### Example 1: Default Configuration (No Configuration Needed)

If you don't specify anything, all VMs use defaults:

```hcl
variable "nb_vm" {
  default = 3
}

# No vm_config or vm_config_override specified - uses all defaults
# Result: 3 VMs, each with 4 cores, 10GiB RAM, connected only to restrictedbr0
```

### Example 2: Custom Base Configuration

Set custom defaults for all VMs using `vm_config`:

```hcl
variable "nb_vm" {
  default = 3
}

variable "vm_config" {
  default = {
    cores          = "8"
    memory         = "16GiB"
    root_disk_size = "100GiB"
    nb_osd         = 4
    osd_disk_size  = "50GiB"
    compute_nets   = []
  }
}
```

### Example 3: Override Specific VMs

Use `vm_config_override` to customize individual VMs while keeping base defaults:

```hcl
variable "nb_vm" {
  default = 3
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
    # vm0: Control plane - more resources
    vm0 = {
      cores  = "6"
      memory = "20GiB"
    }
    # vm1: Compute node with specific networks
    vm1 = {
      cores        = "8"
      compute_nets = ["computebr10", "computebr20"]
    }
    # vm2: Storage-heavy node
    vm2 = {
      nb_osd        = 6
      osd_disk_size = "100GiB"
    }
  }
}
```

### Example 4: Network Isolation

Different workload isolation with override pattern:

```hcl
variable "nb_vm" {
  default = 5
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
    vm0 = { compute_nets = [] }  # Management only (control plane)
    vm1 = { compute_nets = ["computebr10"] }  # Public workloads
    vm2 = { compute_nets = ["computebr20"] }  # Internal workloads
    vm3 = { compute_nets = ["computebr30"] }  # Private workloads
    vm4 = { compute_nets = ["computebr10", "computebr20", "computebr30"] }  # Gateway
  }
}
```

### Example 5: Homogeneous Compute Cluster

All compute nodes with identical specs:

```hcl
variable "nb_vm" {
  default = 4
}

variable "vm_config" {
  default = {
    cores          = "8"
    memory         = "24GiB"
    root_disk_size = "75GiB"
    nb_osd         = 3
    osd_disk_size  = "50GiB"
    compute_nets   = ["computebr10", "computebr20", "computebr30"]
  }
}

# No overrides needed - all VMs use the same config
```

## Network Interface Naming

VMs get network interfaces named according to their attachment:

- **eth0**: Always attached to `restrictedbr0` (management)
- **eth1, eth2, eth3, ...**: Attached to compute networks in the order specified in `compute_nets`

Example:
```hcl
compute_nets = ["computebr10", "computebr30"]
```

Results in:
- eth0 → restrictedbr0 (management)
- eth1 → computebr10
- eth2 → computebr30

## Understanding the Goal

This configuration system allows you to describe **any kind of host infrastructure** for Sunbeam deployments:

- **Flexible topologies**: Mix management-only and multi-network nodes
- **Per-VM control**: Each VM can have unique resources and network attachments
- **Workload isolation**: Use different compute networks for different purposes
- **Management always available**: All nodes can always communicate via restrictedbr0
- **Future-proof**: Easy to add/remove networks or change configurations

## Tips

1. **Always test with fewer VMs first**: Start with `nb_vm = 2` and scale up
2. **Management network is automatic**: You never need to specify `restrictedbr0` in `compute_nets`
3. **Empty list means management only**: Use `compute_nets = []` for control plane nodes
4. **Network names must match**: Use the actual network names (`computebr10`, etc.) from `networking.tf`
5. **Check outputs**: After applying, use `terraform output compute_nodes` to verify your configuration

## Viewing Your Configuration

After deployment, check the configuration:

```bash
terraform output compute_nodes
terraform output network_topology
terraform output compute_network_names
```
