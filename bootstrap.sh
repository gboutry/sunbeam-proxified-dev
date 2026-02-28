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

cidr_host_ip() {
    local cidr="$1"
    local host_index="$2"
    python3 - "$cidr" "$host_index" <<'PY'
import ipaddress
import sys

network = ipaddress.ip_network(sys.argv[1], strict=False)
print(network.network_address + int(sys.argv[2]))
PY
}

configure_split_dns() {
    local iface="$1"
    local domain="$2"
    local dns_ip="$3"

    if ! command -v resolvectl >/dev/null 2>&1; then
        log "WARNING: resolvectl not found; skipping split DNS setup for *.${domain}"
        return 0
    fi

    log "Configuring split DNS: *.${domain} -> ${dns_ip} (iface=${iface})"
    "${SUDO[@]}" resolvectl dns "$iface" "$dns_ip"
    "${SUDO[@]}" resolvectl domain "$iface" "~${domain}"
    "${SUDO[@]}" resolvectl flush-caches || true
}

persist_split_dns() {
    local iface="$1"
    local domain="$2"
    local dns_ip="$3"
    local helper_path="/usr/local/sbin/sunbeam-split-dns"
    local unit_path="/etc/systemd/system/sunbeam-split-dns.service"

    if ! command -v systemctl >/dev/null 2>&1; then
        log "WARNING: systemctl not found; split DNS persistence skipped"
        return 0
    fi

    log "Persisting split DNS configuration across reboot"

    cat <<EOF | "${SUDO[@]}" tee "$helper_path" >/dev/null
#!/usr/bin/env bash
set -euo pipefail
resolvectl dns "${iface}" "${dns_ip}"
resolvectl domain "${iface}" "~${domain}"
resolvectl flush-caches || true
EOF
    "${SUDO[@]}" chmod 0755 "$helper_path"

    cat <<EOF | "${SUDO[@]}" tee "$unit_path" >/dev/null
[Unit]
Description=Apply Sunbeam split DNS configuration
After=network-online.target systemd-resolved.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${helper_path}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    "${SUDO[@]}" systemctl daemon-reload
    "${SUDO[@]}" systemctl enable --now sunbeam-split-dns.service
}

configure_host_domain_resolution() {
    local plan_dir="$1"
    local mode="$2"
    local domain=""
    local mgmt_cidr=""
    local dns_ip=""
    local iface=""

    if [[ "$mode" == "manual" ]]; then
        local topology_json
        if ! topology_json=$(run_as_lxd_group terraform -chdir="$plan_dir" output -json network_topology 2>/dev/null); then
            log "WARNING: unable to read terraform output 'network_topology'; split DNS skipped"
            return 0
        fi

        domain=$(jq -r '.management.domain // empty' <<< "$topology_json")
        mgmt_cidr=$(jq -r '.management.network // empty' <<< "$topology_json")
        dns_ip=$(jq -r '.management.dns_ip // empty' <<< "$topology_json")
        iface="restrictedbr0"
    else
        log "No split DNS auto-configuration defined for MAAS mode"
        return 0
    fi

    if [[ -z "$domain" || -z "$mgmt_cidr" ]]; then
        log "WARNING: missing domain or management CIDR from Terraform outputs; split DNS skipped"
        return 0
    fi

    if [[ -z "$dns_ip" ]]; then
        dns_ip=$(cidr_host_ip "$mgmt_cidr" 2)
    fi
    configure_split_dns "$iface" "$domain" "$dns_ip"
    persist_split_dns "$iface" "$domain" "$dns_ip"
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
  driver: dir
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
        --force \
        --database-uri maas-test-db:/// \
        --maas-url "http://${ip_address}:5240/MAAS"

    # -- Create admin account and save the API key ---------------------------
    log "Creating MAAS admin account"
    if ! output=$("${SUDO[@]}" maas createadmin \
        --username=admin \
        --password=ubuntu \
        --email=admin@example.com 2>&1); then
        if echo "$output" | grep -q "AlreadyExistingUser"; then
            log "MAAS admin account already exists"
        else
            fail "Failed to create MAAS admin account: $output"
        fi
    fi
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
    if ! output=$(maas deployprofile sshkeys create key="$(cat ~/.ssh/id_rsa.pub)" 2>&1); then
        if echo "$output" | grep -q "already been added"; then
            log "SSH key already present in MAAS"
        else
            fail "Failed to add SSH key to MAAS: $output"
        fi
    fi

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
    #  .2–.10    = available for explicit static assignments (auto-reserved by MAAS on use)
    #  .11–.50   = dynamic (MAAS DHCP for commissioning / deployment)
    #  .51–.70   = reserved (OpenStack API VIPs)
    if ! output=$(maas deployprofile ipranges create \
        type=dynamic start_ip=10.10.10.11 end_ip=10.10.10.50 subnet="$subnet_id" 2>&1); then
        if echo "$output" | grep -qi "conflicts with an existing"; then
            log "Dynamic IP range 10.10.10.11-50 already exists"
        else
            fail "Failed to create dynamic IP range 10.10.10.11-50: $output"
        fi
    fi
    if ! output=$(maas deployprofile ipranges create \
        type=reserved start_ip=10.10.10.51 end_ip=10.10.10.70 subnet="$subnet_id" 2>&1); then
        if echo "$output" | grep -qi "conflicts with an existing"; then
            log "Reserved IP range 10.10.10.51-70 already exists"
        else
            fail "Failed to create reserved IP range 10.10.10.51-70: $output"
        fi
    fi

    maas deployprofile subnet update "$subnet_id" gateway_ip=10.10.10.1

    local rack_id
    rack_id=$(maas deployprofile rack-controllers read | jq -r '.[0].system_id')
    maas deployprofile vlan update "$fabric" "$vlan_vid" primary_rack="$rack_id"
    maas deployprofile vlan update "$fabric" "$vlan_vid" dhcp_on=true

    log "Management subnet configured with DHCP"

    maas deployprofile maas set-config name=completed_intro value=true
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

# ---------------------------------------------------------------------------
# Wait until MAAS has discovered all expected LXD bridge subnets.
# MAAS only sees these after VM host registration and a discovery delay.
# ---------------------------------------------------------------------------
maas_wait_for_subnets_discovery() {
    declare -A expected_cidrs=(
        [internal]="10.25.10.0/24"
        [public]="10.25.20.0/24"
        [data]="10.25.30.0/24"
        [storage]="10.25.40.0/24"
        [storage-cluster]="10.25.50.0/24"
    )

    local max_attempts=20
    local attempt=1

    while (( attempt <= max_attempts )); do
        local missing=0
        local subnet_dump
        subnet_dump="$(maas deployprofile subnets read)"

        for space_name in "${!expected_cidrs[@]}"; do
            local cidr="${expected_cidrs[$space_name]}"
            if ! jq -e --arg c "$cidr" '.[] | select(.cidr == $c)' >/dev/null <<< "$subnet_dump"; then
                ((missing++))
            fi
        done

        if (( missing == 0 )); then
            log "MAAS discovered all expected LXD bridge subnets"
            return 0
        fi

        log "Waiting for MAAS subnet discovery (${attempt}/${max_attempts}, missing=${missing})"
        sleep 15
        ((attempt++))
    done

    fail "Timed out waiting for MAAS to discover LXD bridge subnets"
}

# ---------------------------------------------------------------------------
# If MAAS was re-initialized, previously tracked MAAS resources can disappear
# while still being present in Terraform state. Drop only those stale entries.
# ---------------------------------------------------------------------------
maas_reconcile_stale_state() {
    local plan_dir="$1"
    local spaces_json state_list space_name addr

    if ! spaces_json=$(maas deployprofile spaces read 2>/dev/null); then
        log "WARNING: unable to query MAAS spaces for state reconciliation"
        return 0
    fi
    state_list="$(run_as_lxd_group terraform -chdir="$plan_dir" state list 2>/dev/null || true)"

    for space_name in internal public data storage storage-cluster; do
        addr="maas_space.openstack[\"${space_name}\"]"
        if grep -Fxq "$addr" <<< "$state_list" && ! jq -e --arg n "$space_name" '.[] | select(.name == $n)' >/dev/null <<< "$spaces_json"; then
            log "Removing stale Terraform state for missing MAAS space '$space_name'"
            run_as_lxd_group terraform -chdir="$plan_dir" state rm "$addr" >/dev/null
        fi
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
    PLAN_DIR="$SCRIPT_DIR/maas-infra"
    MAAS_API_KEY=$(cat ~/maas-apikey)
    MAAS_API_URL="http://$(ip route get 8.8.8.8 | awk '{print $7; exit}'):5240/MAAS"

    # ---- Bootstrap MAAS<->LXD trust with certificate/key (LXD 6 compatible) ----
    # Trust password was removed in LXD 6.1+, so use a dedicated persistent
    # client cert for MAAS, trust it in LXD, and pass it to Terraform.
    require_cmd openssl
    MAAS_LXD_CERT_DIR="$PLAN_DIR/.secrets"
    MAAS_LXD_CERT_FILE="${MAAS_LXD_CERT_DIR}/maas-lxd-client.crt"
    MAAS_LXD_KEY_FILE="${MAAS_LXD_CERT_DIR}/maas-lxd-client.key"
    MAAS_TFVARS_FILE="${MAAS_LXD_CERT_DIR}/bootstrap.tfvars.json"
    MAAS_LXD_TRUST_NAME="maas-lxd-bootstrap"
    mkdir -p "$MAAS_LXD_CERT_DIR"
    chmod 0700 "$MAAS_LXD_CERT_DIR"

    if [[ ! -s "$MAAS_LXD_CERT_FILE" || ! -s "$MAAS_LXD_KEY_FILE" ]]; then
        log "Generating persistent MAAS LXD client certificate"
        openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
            -keyout "$MAAS_LXD_KEY_FILE" \
            -out "$MAAS_LXD_CERT_FILE" \
            -subj "/CN=maas-lxd-bootstrap" >/dev/null 2>&1
    else
        log "Reusing existing MAAS LXD client certificate"
    fi

    chmod 0644 "$MAAS_LXD_CERT_FILE"
    chmod 0600 "$MAAS_LXD_KEY_FILE"
    maas_lxd_cert_fingerprint=""
    maas_lxd_cert_fingerprint=$(openssl x509 -in "$MAAS_LXD_CERT_FILE" -noout -fingerprint -sha256 \
        | cut -d= -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')
    if run_as_lxd_group lxc config trust list --format json \
        | jq -e --arg fp "$maas_lxd_cert_fingerprint" '.[] | select(.fingerprint == $fp)' >/dev/null; then
        log "MAAS LXD client certificate already trusted"
    else
        log "Trusting MAAS LXD client certificate in local LXD"
        run_as_lxd_group lxc config trust add "$MAAS_LXD_CERT_FILE" --name "$MAAS_LXD_TRUST_NAME" >/dev/null
    fi

    log "Writing Terraform vars file: ${MAAS_TFVARS_FILE}"
    jq -n \
        --arg maas_api_url "$MAAS_API_URL" \
        --arg maas_api_key "$MAAS_API_KEY" \
        --arg lxd_host_address "https://127.0.0.1:8443" \
                --arg lxd_provider_address "unix:///var/snap/lxd/common/lxd/unix.socket" \
        --arg maas_lxd_client_certificate_file "$MAAS_LXD_CERT_FILE" \
        --arg maas_lxd_client_key_file "$MAAS_LXD_KEY_FILE" \
        '{
          maas_api_url: $maas_api_url,
          maas_api_key: $maas_api_key,
          lxd_host_address: $lxd_host_address,
                    lxd_provider_address: $lxd_provider_address,
          maas_lxd_client_certificate_file: $maas_lxd_client_certificate_file,
          maas_lxd_client_key_file: $maas_lxd_client_key_file
        }' > "$MAAS_TFVARS_FILE"
    chmod 0600 "$MAAS_TFVARS_FILE"

    log "Running terraform init (maas-infra)"
    run_as_lxd_group terraform -chdir="$PLAN_DIR" init -input=false

    # ---- Phase 1a: create LXD bridges first ---------------------------------
    # MAAS named binds DNS sockets on discovered interfaces and can race with
    # LXD bridge creation. Stop MAAS during this phase to avoid dnsmasq bind
    # conflicts on 10.25.x.1, then bring it back before MAAS API resources.
    phase1a_maas_stopped=false
    if command -v systemctl >/dev/null 2>&1; then
        log "Stopping MAAS before phase 1a to avoid DNS socket conflicts"
        "${SUDO[@]}" systemctl stop snap.maas.pebble.service
        phase1a_maas_stopped=true
    fi

    log "Terraform apply — phase 1a: LXD bridge networks"
    phase1a_status=0
    if run_as_lxd_group terraform -chdir="$PLAN_DIR" apply \
        -input=false -auto-approve \
        -target=lxd_network.maas_networks \
        -var-file="$MAAS_TFVARS_FILE" \
        "$@"; then
        :
    else
        phase1a_status=$?
    fi

    if [[ "$phase1a_maas_stopped" == "true" ]]; then
        log "Starting MAAS after phase 1a"
        "${SUDO[@]}" systemctl start snap.maas.pebble.service
        sleep 30
    fi
    (( phase1a_status == 0 )) || exit "$phase1a_status"

    # ---- Phase 1b: register VM host and create MAAS spaces ------------------
    maas_reconcile_stale_state "$PLAN_DIR"
    # MAAS discovers LXD bridges through the VM host after registration/refresh.
    log "Terraform apply — phase 1b: VM host registration and MAAS spaces"
    run_as_lxd_group terraform -chdir="$PLAN_DIR" apply \
        -input=false -auto-approve \
        -target=maas_space.openstack \
        -target=maas_vm_host.lxd \
        -var-file="$MAAS_TFVARS_FILE" \
        "$@"

    # ---- Wait for MAAS to discover bridge subnets before VLAN/space mapping -
    maas_wait_for_subnets_discovery

    # ---- Assign VLANs to spaces (spaces exist; MAAS has had time to discover bridges) ----
    maas_assign_vlans_to_spaces

    # ---- Phase 2: full apply — composes VMs with isolation NICs + tags -----
    log "Terraform apply — phase 2: full deployment"
    run_as_lxd_group terraform -chdir="$PLAN_DIR" apply \
        -input=false -auto-approve \
        -var-file="$MAAS_TFVARS_FILE" \
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
configure_host_domain_resolution "$PLAN_DIR" "$MODE"
log "Bootstrap complete"
log "Testbed description: $PLAN_DIR/testbed.yaml"
