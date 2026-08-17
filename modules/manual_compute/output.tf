output "ip" {
  value = var.management_ip
}

output "name" {
  value = lxd_instance.compute.name
}

output "fqdn" {
  value = local.fqdn
}

output "osds" {
  value = lxd_storage_volume.osd[*].name
}

output "hostname" {
  value = var.hostname
}

output "cores" {
  value = var.cores
}

output "memory" {
  value = var.memory
}

output "root_disk_size" {
  value = var.root_disk_size
}

output "roles" {
  value = var.roles
}

output "nb_osd" {
  value = var.nb_osd
}

output "osd_disk_size" {
  value = var.osd_disk_size
}

output "compute_nets" {
  value = var.compute_nets
}

output "isolation_nets" {
  value = var.isolation_nets
}
