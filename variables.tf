variable "nb_vm" {
  default = 3
}

variable "use_proxy" {
  description = "Whether to deploy a squid proxy and route traffic through it"
  type        = bool
  default     = false
}

variable "vm_config" {
  description = "Default configuration for all VMs"
  type = object({
    cores          = string
    memory         = string
    root_disk_size = string
    nb_osd         = number
    osd_disk_size  = string
    compute_nets   = list(string)
    isolation_nets = optional(list(string))
    roles          = list(string)
  })
  default = {
    cores          = "6"
    memory         = "18GiB"
    root_disk_size = "120GiB"
    nb_osd         = 3
    osd_disk_size  = "50GiB"
    compute_nets   = ["computebr10"]
    roles          = ["control", "compute", "storage"]
  }
}

variable "vm_config_override" {
  description = "Override configuration for specific VMs (merged with vm_config defaults)"
  type = map(object({
    cores          = optional(string)
    memory         = optional(string)
    root_disk_size = optional(string)
    nb_osd         = optional(number)
    osd_disk_size  = optional(string)
    compute_nets   = optional(list(string))
    isolation_nets = optional(list(string))
    roles          = optional(list(string))
  }))
  default = {}
}

variable "enable_maas" {
  description = "Enable MAAS mode: deploys juju-controller and sunbeam VMs, creates named MAAS networks, and generates a MAAS testbed.yaml"
  type        = bool
  default     = false
}

variable "lxd_host_address" {
  description = "Address of the LXD host server (used in MAAS testbed.yaml for VM host registration)"
  type        = string
}

variable "maas_network_cidrs" {
  description = "CIDR ranges for MAAS cloud networks (only used when enable_maas = true)"
  type = object({
    internal        = string
    public          = string
    data            = string
    storage         = string
    storage_cluster = string
  })
  default = {
    internal        = "10.25.10.0/24"
    public          = "10.25.20.0/24"
    data            = "10.25.30.0/24"
    storage         = "10.25.40.0/24"
    storage_cluster = "10.25.50.0/24"
  }
}
