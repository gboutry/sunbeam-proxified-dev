variable "hostname" {}
variable "management_domain" {}
variable "management_net" {}
variable "management_dns" {}
variable "management_ip" {}
variable "compute_nets" {}
variable "isolation_nets" {
  description = "Additional NICs for traffic isolation (e.g. MAAS spaces for internal/data/storage). Attached after compute_nets; MAAS configures IPs on these post-enrollment."
  type        = list(string)
  default     = []
}
variable "proxy_url" {}
variable "proxy_ip" {}
variable "no_proxy" {}
variable "cores" {}
variable "memory" {}
variable "root_disk_size" {}
variable "roles" { }
variable "nb_osd" {
  default = 3
}
variable "osd_disk_size" {
  default = "50GiB"
}
variable "use_proxy" {
  type = bool
}
variable "ssh_public_key" {
  description = "SSH public key to authorize for the ubuntu user"
  type        = string
}
