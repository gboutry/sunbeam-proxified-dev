#!/usr/bin/env bash
#
# Usage:
#   ./bootstrap.sh [--maas] [extra terraform args...]
#
# Without '--maas': deploys manual-infra (LXD-only, no MAAS).
# With    '--maas': installs and configures MAAS + LXD, then deploys maas-infra.
#
# The MAAS mode runs terraform in two phases:
#   Phase 1  — creates LXD bridges and registers the LXD VM host in MAAS.
#   (cert trust step performed by this script between phases)
#   Phase 2  — creates VMs via MAAS and assigns role tags.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { printf '[bootstrap] %s\n' "$*"; }

fail() { printf '[bootstrap] ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

if [[ "${EUID}" -eq 0 ]]; then
    SUDO=()
else
    SUDO=(sudo)
fi

run_as_lxd_group() {
    if [[ "${EUID}" -eq 0 ]]; then
        "$@"
        return
    fi

    local escaped=()
    local arg
    for arg in "$@"; do
        escaped+=("$(printf '%q' "$arg")")
    done

    sg lxd -c "${escaped[*]}"
}

require_cmd python3

find_largest_disk() {
    local output
    local disk

    if [[ -f "$SCRIPT_DIR/find_largest_unused_disk.py" ]]; then
        output="$(python3 "$SCRIPT_DIR/find_largest_unused_disk.py" 2>/dev/null || true)"
        disk="$(printf '%s\n' "$output" | grep -Eo '/dev/[[:alnum:]_.-]+' | tail -n1 || true)"
        if [[ -n "$disk" ]]; then
            printf '%s\n' "$disk"
            return 0
        fi
    fi

    if [[ -f "$SCRIPT_DIR/find_largest_disk.py" ]]; then
        output="$(python3 "$SCRIPT_DIR/find_largest_disk.py" 2>/dev/null || true)"
        disk="$(printf '%s\n' "$output" | grep -Eo '/dev/[[:alnum:]_.-]+' | tail -n1 || true)"
        if [[ -n "$disk" ]]; then
            printf '%s\n' "$disk"
            return 0
        fi
    fi

    return 1
}

# ---------------------------------------------------------------------------
# LXD initialisation preseeds
# ---------------------------------------------------------------------------

lxd_init() {
    local disk="$1"
    local mode="$2"
    local network_name="lxdbr0"
    local network_config="    ipv4.address: auto
    ipv4.nat: \"true\"
    ipv6.address: none"

    if [[ "$mode" == "maas" ]]; then
        network_name="mgmt"
        network_config="    ipv4.address: 10.10.10.1/24
    ipv4.nat: \"true\"
    ipv4.dhcp: \"false\"
    ipv6.address: none"
    fi

    cat <<EOF | run_as_lxd_group lxd init --preseed >/dev/null
networks:
- config:
${network_config}
  name: ${network_name}
  project: default
storage_pools:
- name: default
  driver: zfs
  config:
    source: ${disk}
profiles:
- devices:
    eth0:
      name: eth0
      network: ${network_name}
      type: nic
    root:
      path: /
      pool: default
      type: disk
  name: default
EOF
}

# ---------------------------------------------------------------------------
# MAAS bootstrap  (everything Terraform cannot do)
# ---------------------------------------------------------------------------
bootstrap_maas() {
    local ip_address
    ip_address=$(ip route get 8.8.8.8 | awk '{print $7; exit}')

    # -- Expose LXD API so MAAS can reach it --------------------------------
    log "Configuring LXD HTTPS address (127.0.0.1:8443)"
    run_as_lxd_group lxc config set core.https_address 127.0.0.1:8443

    # -- Install MAAS --------------------------------------------------------
    log "Installing MAAS 3.7"
    "${SUDO[@]}" snap install --channel=3.7/stable maas
    "${SUDO[@]}" snap install --channel=3.7/stable maas-test-db

    # -- Initialise region+rack controller -----------------------------------
    log "Initialising MAAS region+rack controller"
    "${SUDO[@]}" maas init region+rack \
        --database-uri maas-test-db:/// \
        --maas-url "http://${ip_address}:5240/MAAS"

    # -- Create admin account and save the API key ---------------------------
    log "Creating MAAS admin account"
    "${SUDO[@]}" maas createadmin \
        --username=admin \
        --password=ubuntu \
        --email=admin@example.com
    "${SUDO[@]}" maas apikey --username=admin > ~/maas-apikey

    sleep 30

    # -- Log in to MAAS CLI --------------------------------------------------
    log "Logging in to MAAS CLI"
    maas login deployprofile "http://${ip_address}:5240/MAAS" - < ~/maas-apikey

    # -- Import Ubuntu Noble boot resources ----------------------------------
    log "Triggering boot resource import"
    maas deployprofile boot-resources import
    sleep 60

    log "Selecting Ubuntu 24.04 LTS (Noble) for download"
    if ! output=$(maas deployprofile boot-source-selections create 1 \
        os="ubuntu" release="noble" arches="amd64" subarches="*" labels="*" 2>&1); then
        if echo "$output" | grep -q "already exists"; then
            log "Boot source selection already exists"
        else
            fail "Failed to create boot source selection: $output"
        fi
    fi
    maas deployprofile boot-resources import

    log "Waiting for boot resource import to complete"
    while true; do
        if [[ "$(maas deployprofile boot-resources is-importing)" == "false" ]]; then
            log "Boot resources import complete"
            break
        fi
        log "Still importing (waiting 30s)"
        sleep 30
    done

    # -- Static MAAS configuration -------------------------------------------
    maas deployprofile maas set-config name=network_discovery         value="disabled"
    maas deployprofile maas set-config name=kernel_opts               value="net.ifnames=0"
    maas deployprofile maas set-config name=disk_erase_with_secure_erase value=false
    maas deployprofile maas set-config name=disk_erase_with_quick_erase  value=true
    maas deployprofile maas set-config name=enable_disk_erasing_on_release value=true
    maas deployprofile maas set-config name=node_timeout              value=1200

    # -- Restart dance: MAAS tcp/53 conflicts with LXD dnsmasq --------------
    log "Restarting MAAS (resolves tcp/53 conflict with LXD DNS)"
    "${SUDO[@]}" systemctl stop  snap.maas.pebble.service
    sleep 5
    "${SUDO[@]}" systemctl start snap.maas.pebble.service
    sleep 30

    # -- SSH key for MAAS agents (commissioning / deployment) ----------------
    log "Adding SSH key to MAAS"
    [[ -f ~/.ssh/id_rsa ]] || ssh-keygen -t rsa -N "" -q -f ~/.ssh/id_rsa
    maas deployprofile sshkeys create key="$(cat ~/.ssh/id_rsa.pub)"

    # -- Wait for MAAS to discover the mgmt bridge ---------------------------
    log "Waiting for MAAS to discover the mgmt network (60s)"
    sleep 60

    # -- Configure the management subnet in MAAS -----------------------------
    # MAAS needs DHCP on this subnet to commission/deploy VMs.
    local mgmt_cidr="10.10.10.0/24"
    log "Configuring management subnet ${mgmt_cidr}"

    local subnet_json
    subnet_json=$(maas deployprofile subnets read \
        | jq -c --arg c "$mgmt_cidr" '.[] | select(.cidr == $c)')
    [[ -n "$subnet_json" ]] || fail "Subnet ${mgmt_cidr} not visible in MAAS yet"

    local subnet_id vlan_vid fabric
    subnet_id=$(jq -r .id        <<< "$subnet_json")
    vlan_vid=$(jq -r '.vlan.vid' <<< "$subnet_json")
    fabric=$(jq -r '.vlan.fabric' <<< "$subnet_json")

    # Create the 'management' MAAS space (matches testbed.yaml spaces section)
    if ! maas deployprofile spaces read \
            | jq -e '.[] | select(.name == "management")' >/dev/null 2>&1; then
        maas deployprofile spaces create name=management
    fi
    maas deployprofile vlan update "$fabric" "$vlan_vid" space=management

    # IP layout on 10.10.10.0/24:
    #  .1        = gateway (LXD bridge)
    #  .2–.10    = reserved (infrastructure)
    #  .11–.50   = dynamic (MAAS DHCP for commissioning / deployment)
    #  .51–.70   = reserved (OpenStack API VIPs)
    maas deployprofile ipranges create \
        type=reserved start_ip=10.10.10.2  end_ip=10.10.10.10  subnet="$subnet_id"
    maas deployprofile ipranges create \
        type=dynamic  start_ip=10.10.10.11 end_ip=10.10.10.50  subnet="$subnet_id"
    maas deployprofile ipranges create \
        type=reserved start_ip=10.10.10.51 end_ip=10.10.10.70  subnet="$subnet_id"

    maas deployprofile subnet update "$subnet_id" gateway_ip=10.10.10.1

    local rack_id
    rack_id=$(maas deployprofile rack-controllers read | jq -r '.[0].system_id')
    maas deployprofile vlan update "$fabric" "$vlan_vid" primary_rack="$rack_id"
    maas deployprofile vlan update "$fabric" "$vlan_vid" dhcp_on=true

    log "Management subnet configured with DHCP"
}

# ---------------------------------------------------------------------------
# Trust the certificate MAAS generated for itself, then refresh the VM host.
# Called between phase-1 and phase-2 terraform applies.
# ---------------------------------------------------------------------------
maas_trust_lxd_cert() {
    log "Retrieving MAAS certificate and adding to LXD trust"

    local vm_host_id
    vm_host_id=$(maas deployprofile vm-hosts read | jq -r '.[0].id')
    [[ -n "$vm_host_id" ]] || fail "No VM host found in MAAS — phase-1 apply may have failed"

    maas deployprofile vm-host parameters "$vm_host_id" \
        | jq -r '.certificate' > /tmp/maas_lxd.crt
    run_as_lxd_group lxc config trust add /tmp/maas_lxd.crt
    rm -f /tmp/maas_lxd.crt

    log "Refreshing MAAS VM host"
    maas deployprofile vm-host refresh "$vm_host_id"
}

# ---------------------------------------------------------------------------
# Assign each OpenStack bridge's VLAN to its MAAS space.
# Spaces are created by Terraform (maas_space.openstack in networking.tf).
# This step is separate because MAAS discovers LXD bridges asynchronously
# (~60s), making the fabric/VLAN IDs unavailable at Terraform apply time.
#
# Must run AFTER phase-1 apply (bridges + spaces exist) and BEFORE phase-2
# apply (VMs are composed with subnet_cidr constraints that require the
# bridge↔space mapping to be in place for MAAS to route NICs correctly).
#
# If you customised maas_network_cidrs in your tfvars, adjust accordingly.
# ---------------------------------------------------------------------------
maas_assign_vlans_to_spaces() {
    # space-name → CIDR (matches maas-infra defaults)
    declare -A space_cidrs=(
        [internal]="10.25.10.0/24"
        [public]="10.25.20.0/24"
        [data]="10.25.30.0/24"
        [storage]="10.25.40.0/24"
        [storage-cluster]="10.25.50.0/24"
    )

    log "Waiting for MAAS to discover OpenStack bridges (60s)"
    sleep 60

    for space_name in "${!space_cidrs[@]}"; do
        local cidr="${space_cidrs[$space_name]}"

        local subnet_json
        subnet_json=$(maas deployprofile subnets read \
            | jq -c --arg c "$cidr" '.[] | select(.cidr == $c)')
        if [[ -z "$subnet_json" ]]; then
            log "WARNING: subnet $cidr ($space_name) not visible in MAAS yet, skipping VLAN assignment"
            continue
        fi

        local vlan_vid fabric
        vlan_vid=$(jq -r '.vlan.vid'   <<< "$subnet_json")
        fabric=$(jq -r '.vlan.fabric'  <<< "$subnet_json")

        maas deployprofile vlan update "$fabric" "$vlan_vid" space="$space_name"
        log "Space '$space_name' ← VLAN $vlan_vid on fabric $fabric"
    done
}

# ===========================================================================
# Main
# ===========================================================================

# Consume the optional '--maas' first argument; remaining args forwarded to
# terraform apply (e.g. -var-file custom.tfvars).
if [[ "${1:-}" == "--maas" ]]; then
    MODE="maas"
    shift
else
    MODE="manual"
fi

# -- Detect storage disk -----------------------------------------------------
largest_disk="$(find_largest_disk || true)"
[[ -n "$largest_disk" ]] || fail "Unable to detect a largest unused disk"

# -- Install LXD if missing --------------------------------------------------
if ! command -v lxc >/dev/null 2>&1 || ! command -v lxd >/dev/null 2>&1; then
    require_cmd snap
    log "Installing LXD via snap"
    "${SUDO[@]}" snap install lxd
fi

"${SUDO[@]}" snap start lxd >/dev/null 2>&1 || true
if [[ "${EUID}" -ne 0 ]]; then
    require_cmd sg
    if ! id -nG "${USER}" | grep -qw lxd; then
        log "Adding user ${USER} to lxd group"
        "${SUDO[@]}" usermod -aG lxd "${USER}"
    fi
fi

run_as_lxd_group lxd waitready --timeout=60

# -- Initialise LXD ----------------------------------------------------------
lxd_initialized() {
    run_as_lxd_group lxc storage show default >/dev/null 2>&1
}

if lxd_initialized; then
    log "LXD already initialised"
else
    log "Initialising LXD (${MODE} mode) using disk ${largest_disk}"
    lxd_init "$largest_disk" "$MODE" || fail "LXD initialisation failed"
fi

# -- Install Terraform if missing --------------------------------------------
if ! command -v terraform >/dev/null 2>&1; then
    require_cmd snap
    log "Installing Terraform via snap"
    "${SUDO[@]}" snap install terraform --classic
fi

# ===========================================================================
# Mode-specific deployment
# ===========================================================================

if [[ "$MODE" == "maas" ]]; then
    # ---- MAAS system setup (everything Terraform cannot do) ----------------
    bootstrap_maas

    MAAS_API_KEY=$(cat ~/maas-apikey)
    PLAN_DIR="$SCRIPT_DIR/maas-infra"

    log "Running terraform init (maas-infra)"
    run_as_lxd_group terraform -chdir="$PLAN_DIR" init -input=false

    # ---- Phase 1: LXD bridges + MAAS spaces + VM host registration ----------
    # maas_space.openstack is included here (no timing dependency).
    # VM host registration creates a MAAS-side record; LXD connectivity is
    # not yet possible until we add the MAAS certificate to LXD trust.
    log "Terraform apply — phase 1: bridges, spaces, VM host registration"
    run_as_lxd_group terraform -chdir="$PLAN_DIR" apply \
        -input=false -auto-approve \
        -target=lxd_network.maas_networks \
        -target=maas_space.openstack \
        -target=maas_vm_host.lxd \
        -var="maas_api_url=http://$(ip route get 8.8.8.8 | awk '{print $7; exit}'):5240/MAAS" \
        -var="maas_api_key=${MAAS_API_KEY}" \
        -var="lxd_host_address=https://127.0.0.1:8443" \
        "$@"

    # ---- Trust MAAS certificate so the VM host becomes operational ---------
    maas_trust_lxd_cert

    # ---- Assign VLANs to spaces (spaces exist; MAAS has had time to discover bridges) ----
    maas_assign_vlans_to_spaces

    # ---- Phase 2: full apply — composes VMs with isolation NICs + tags -----
    log "Terraform apply — phase 2: full deployment"
    run_as_lxd_group terraform -chdir="$PLAN_DIR" apply \
        -input=false -auto-approve \
        -var="maas_api_url=http://$(ip route get 8.8.8.8 | awk '{print $7; exit}'):5240/MAAS" \
        -var="maas_api_key=${MAAS_API_KEY}" \
        -var="lxd_host_address=https://127.0.0.1:8443" \
        "$@"

else
    PLAN_DIR="$SCRIPT_DIR/manual-infra"

    log "Running terraform init (manual-infra)"
    run_as_lxd_group terraform -chdir="$PLAN_DIR" init -input=false

    log "Running terraform apply (forwarding script arguments)"
    run_as_lxd_group terraform -chdir="$PLAN_DIR" apply \
        -input=false -auto-approve "$@"
fi

[[ -s "$PLAN_DIR/testbed.yaml" ]] || fail "testbed.yaml was not generated"
log "Bootstrap complete"
log "Testbed description: $PLAN_DIR/testbed.yaml"
