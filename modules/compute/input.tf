variable "hostname" {}
variable "management_domain" {}
variable "management_net" {}
variable "management_dns" {}
variable "compute_nets" {}
variable "proxy_url" {}
variable "proxy_ip" {}
variable "no_proxy" {}
variable "cores" {}
variable "memory" {}
variable "root_disk_size" {}
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
