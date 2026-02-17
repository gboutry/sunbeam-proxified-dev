#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log() {
    printf '[bootstrap] %s\n' "$*"
}

fail() {
    printf '[bootstrap] ERROR: %s\n' "$*" >&2
    exit 1
}

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

largest_disk="$(find_largest_disk || true)"
[[ -n "$largest_disk" ]] || fail "Unable to detect a largest unused disk"

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

if ! command -v terraform >/dev/null 2>&1; then
    require_cmd snap
    log "Installing Terraform via snap"
    "${SUDO[@]}" snap install terraform --classic
fi

lxd_initialized() {
    run_as_lxd_group lxc storage show default >/dev/null 2>&1
}

lxd_init() {
    local disk="$1"

    cat <<EOF | run_as_lxd_group lxd init --preseed >/dev/null
networks:
- config:
    ipv4.address: auto
    ipv4.nat: "true"
    ipv6.address: none
  name: lxdbr0
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
      network: lxdbr0
      type: nic
    root:
      path: /
      pool: default
      type: disk
  name: default
EOF
}

if lxd_initialized; then
    log "LXD is already initialized with a default storage pool"
else
    log "Initializing LXD using disk ${largest_disk} for the default storage pool"

    init_ok=0
    if lxd_init "$largest_disk"; then
        log "LXD initialized with driver zfs"
        init_ok=1
    fi

    [[ "$init_ok" -eq 1 ]] || fail "LXD initialization failed for drivers: zfs"
fi

log "Running terraform init"
run_as_lxd_group terraform init -input=false

log "Running terraform apply (forwarding script arguments)"
run_as_lxd_group terraform apply -input=false "$@"

if [[ ! -s "$SCRIPT_DIR/testbed.yaml" ]]; then
    log "Generating testbed.yaml from Terraform output"
    run_as_lxd_group terraform output -raw infrastructure > "$SCRIPT_DIR/testbed.yaml"
fi

[[ -s "$SCRIPT_DIR/testbed.yaml" ]] || fail "testbed.yaml was not generated"

log "Bootstrap complete"
log "Testbed description available at: $SCRIPT_DIR/testbed.yaml"
