output "system_id" { value = maas_vm_host_machine.compute.id }
output "hostname" { value = var.hostname }
output "name" { value = var.hostname }
output "fqdn" { value = local.fqdn }
output "ip" { value = var.management_ip }
output "roles" { value = var.roles }
output "cores" { value = var.cores }
output "memory" { value = var.memory }
output "root_disk_size" { value = var.root_disk_size }
output "nb_osd" { value = var.nb_osd }
output "osd_disk_size" { value = var.osd_disk_size }
output "osds" {
  value = [for i in range(var.nb_osd) : "/dev/disk/by-dname/sd${substr("bcdefghijklmnopqrstuvwxyz", i, 1)}"]
}
output "compute_nets" { value = [] }
output "isolation_nets" { value = [] }
output "isolation_cidrs" { value = var.isolation_cidrs }
