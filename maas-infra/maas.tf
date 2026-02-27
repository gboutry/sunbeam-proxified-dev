locals {
  maas_all_machines = concat(
    [for vm in module.maas_compute : { id = vm.system_id, roles = vm.roles, nb_osd = vm.nb_osd }],
    [{ id = module.maas_juju_controller.system_id, roles = module.maas_juju_controller.roles, nb_osd = module.maas_juju_controller.nb_osd }],
    [{ id = module.maas_sunbeam.system_id, roles = module.maas_sunbeam.roles, nb_osd = module.maas_sunbeam.nb_osd }],
  )
  maas_machine_ids = [for m in local.maas_all_machines : m.id]
  maas_role_to_machines = {
    for role in distinct(flatten([for m in local.maas_all_machines : m.roles])) : role => [
      for m in local.maas_all_machines : m.id if contains(m.roles, role)
    ]
  }
}

resource "maas_vm_host" "lxd" {
  type          = "lxd"
  power_address = var.lxd_host_address
  certificate   = trimspace(file(var.maas_lxd_client_certificate_file))
  key           = trimspace(file(var.maas_lxd_client_key_file))
  name          = "lxd-host"
}

module "maas_juju_controller" {
  depends_on = [maas_vm_host.lxd]
  source     = "../modules/maas_compute"

  hostname               = "juju-controller"
  management_domain      = var.management_domain
  management_subnet_cidr = "10.10.10.0/24"
  management_ip          = cidrhost("10.10.10.0/24", 81)
  vm_host                = maas_vm_host.lxd.id

  cores           = "2"
  memory          = "4GiB"
  root_disk_size  = "40GiB"
  nb_osd          = 0
  osd_disk_size   = "50GiB"
  roles           = ["juju-controller"]
  isolation_cidrs = []
}

module "maas_sunbeam" {
  depends_on = [maas_vm_host.lxd]
  source     = "../modules/maas_compute"

  hostname               = "sunbeam"
  management_domain      = var.management_domain
  management_subnet_cidr = "10.10.10.0/24"
  management_ip          = cidrhost("10.10.10.0/24", 82)
  vm_host                = maas_vm_host.lxd.id

  cores           = "2"
  memory          = "4GiB"
  root_disk_size  = "40GiB"
  nb_osd          = 0
  osd_disk_size   = "50GiB"
  roles           = ["sunbeam"]
  isolation_cidrs = []
}

resource "maas_tag" "roles" {
  for_each = local.maas_role_to_machines
  name     = each.key
  machines = each.value
}

resource "maas_tag" "deployment" {
  name     = "openstack-${var.deployment_name}"
  machines = local.maas_machine_ids
}

resource "terraform_data" "maas_interface_and_disk_tags" {
  depends_on = [
    module.maas_compute,
    module.maas_juju_controller,
    module.maas_sunbeam,
    maas_tag.deployment,
    maas_tag.roles,
  ]

  triggers_replace = {
    machine_ids = join(",", sort(local.maas_machine_ids))
    public_cidr = var.maas_network_cidrs.public
    osd_map     = jsonencode({ for m in local.maas_all_machines : m.id => m.nb_osd })
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      profile="deployprofile"
      machine_ids='${join(" ", local.maas_machine_ids)}'
      public_cidr='${var.maas_network_cidrs.public}'
      machine_osd_map='${jsonencode({ for m in local.maas_all_machines : m.id => m.nb_osd })}'

      maas "$profile" users whoami >/dev/null 2>&1 || {
        echo "MAAS CLI profile '$profile' not configured; run bootstrap.sh --maas first." >&2
        exit 1
      }

      for system_id in $machine_ids; do
        while read -r interface_id; do
          [[ -n "$interface_id" ]] || continue
          maas "$profile" interface add-tag "$system_id" "$interface_id" tag=neutron:physnet1 >/dev/null
        done < <(
          maas "$profile" interfaces read "$system_id" \
            | jq -r --arg cidr "$public_cidr" '.[] | select(any(.links[]?; .subnet.cidr == $cidr)) | .id'
        )

        nb_osd=$(jq -r --arg system_id "$system_id" '.[$system_id] // 0' <<< "$machine_osd_map")
        if [[ "$nb_osd" -gt 0 ]]; then
          while read -r block_id; do
            [[ -n "$block_id" ]] || continue
            maas "$profile" block-device add-tag "$system_id" "$block_id" tag=ceph >/dev/null
          done < <(
            maas "$profile" block-devices read "$system_id" \
              | jq -r --argjson n "$nb_osd" '[.[] | select(.used_for == "Unused")] | sort_by(.id) | .[:$n] | .[].id'
          )
        fi
      done
    EOT
  }
}
