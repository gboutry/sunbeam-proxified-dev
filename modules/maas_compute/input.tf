variable "hostname" { type = string }
variable "management_domain" { type = string }
variable "management_subnet_cidr" {
  description = "Management subnet CIDR used for the primary NIC."
  type        = string
  default     = "10.10.10.0/24"
}
variable "management_ip" {
  description = "Optional static management IP for eth0."
  type        = string
  default     = ""
}
variable "vm_host" {
  description = "MAAS system_id or name of the LXD VM host"
  type        = string
}
variable "cores" { type = string }
variable "memory" { type = string }         # "18GiB" format, parsed to MiB internally
variable "root_disk_size" { type = string } # "120GiB" format, parsed to GB internally
variable "nb_osd" {
  type    = number
  default = 0
}
variable "osd_disk_size" {
  type    = string
  default = "50GiB"
}
variable "roles" {
  type    = list(string)
  default = []
}

variable "isolation_cidrs" {
  description = "Subnet CIDRs for additional NICs (OpenStack isolation networks). Each CIDR maps to one extra NIC on the corresponding MAAS-managed bridge."
  type        = list(string)
  default     = []
}
