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
    roles          = optional(list(string))
  }))
  default = {}
}
