variable "nb_vm" {
  default = 3
}

variable "vm_config" {
  description = "Default configuration for all VMs"
  type = object({
    cores          = string
    memory         = string
    root_disk_size = string
    nb_osd         = number
    osd_disk_size  = string
    roles          = list(string)
  })
  default = {
    cores          = "6"
    memory         = "18GiB"
    root_disk_size = "120GiB"
    nb_osd         = 3
    osd_disk_size  = "50GiB"
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
    roles          = optional(list(string))
  }))
  default = {}
}

variable "lxd_host_address" {
  description = "Address of the LXD host server (used by LXD provider and passed to MAAS as VM host power address)"
  type        = string
}

variable "lxd_provider_address" {
  description = "Optional address for Terraform LXD provider connectivity; if empty, lxd_host_address is used"
  type        = string
  default     = ""
}

variable "maas_api_url" {
  description = "MAAS API URL"
  type        = string
  default     = "http://localhost:5240/MAAS"
}

variable "maas_api_key" {
  description = "MAAS API key"
  type        = string
  sensitive   = true
}

variable "maas_lxd_client_certificate_file" {
  description = "Required path to PEM client certificate that MAAS uses to authenticate to LXD (must be trusted by LXD)"
  type        = string
}

variable "maas_lxd_client_key_file" {
  description = "Required path to PEM private key paired with maas_lxd_client_certificate_file"
  type        = string
  sensitive   = true
}

variable "management_domain" {
  description = "DNS domain for MAAS machines (used to construct FQDNs in testbed.yaml)"
  type        = string
  default     = "maas"
}

variable "maas_network_cidrs" {
  description = "CIDR ranges for MAAS cloud networks"
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
