#!/usr/bin/env bash
# =============================================================================
# Common functions for op-reth benchmark scripts
# =============================================================================
# Source this file in other scripts:
#   source "$(dirname "$0")/common.sh"
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Script directory (for finding config.py)
# -----------------------------------------------------------------------------
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPTS_DIR")"

# -----------------------------------------------------------------------------
# Colors
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Logging functions
# -----------------------------------------------------------------------------
info() {
    echo -e "${BLUE}==>${NC} $*"
}

success() {
    echo -e "${GREEN}==>${NC} $*"
}

warn() {
    echo -e "${YELLOW}WARN:${NC} $*"
}

error() {
    echo -e "${RED}ERROR:${NC} $*" >&2
}

die() {
    error "$@"
    exit 1
}

# -----------------------------------------------------------------------------
# Config loading (via config.py)
# -----------------------------------------------------------------------------
cfg() {
    # Get a config value: cfg project.project_id
    python3 "$SCRIPTS_DIR/config.py" "$1"
}

# Load common config values
load_config() {
    PROJECT_ID=$(cfg project.project_id)
    REGION=$(cfg project.region)
    ZONE=$(cfg project.zone)
    GCS_BUCKET=$(cfg project.gcs_bucket)
    CHAIN_NETWORK=$(cfg project.chain_network)
    SNAPSHOT_NAME=$(cfg snapshot.name)
    
    # Build config
    RETH_REPO=$(cfg build.reth_repo)
    RETH_BRANCH=$(cfg build.reth_branch)
    OP_NODE_VERSION=$(cfg build.op_node_version)
    
    # Derived values
    if [[ "$CHAIN_NETWORK" == "base-mainnet" ]]; then
        L1_NETWORK="mainnet"
    else
        L1_NETWORK="holesky"
    fi
    
    export PROJECT_ID REGION ZONE GCS_BUCKET CHAIN_NETWORK SNAPSHOT_NAME
    export RETH_REPO RETH_BRANCH OP_NODE_VERSION L1_NETWORK
}

# -----------------------------------------------------------------------------
# Validation functions
# -----------------------------------------------------------------------------
require_var() {
    local var_name="$1"
    local var_value="${!var_name:-}"
    local usage="${2:-}"
    
    if [[ -z "$var_value" ]]; then
        error "$var_name is required"
        if [[ -n "$usage" ]]; then
            echo ""
            echo "Usage: $usage"
        fi
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Interactive confirmation
# -----------------------------------------------------------------------------
confirm() {
    local msg="${1:-Are you sure?}"
    local response
    read -p "$msg [y/N] " response
    [[ "$response" =~ ^[Yy]$ ]]
}

# -----------------------------------------------------------------------------
# List VMs from config
# -----------------------------------------------------------------------------
list_config_vms() {
    cfg vm | jq -r '.[].name'
}

# -----------------------------------------------------------------------------
# SSH to VM using internal hostname
# -----------------------------------------------------------------------------
ssh_to_vm() {
    local vm_name="$1"
    shift
    local cmd="${*:-}"
    
    load_config
    
    local ssh_args=(
        "$vm_name"
        "--zone=$ZONE"
        "--project=$PROJECT_ID"
        "--ssh-flag=-o Hostname=nic0.$vm_name.$ZONE.c.$PROJECT_ID.internal.gcpnode.com"
    )
    
    if [[ -n "$cmd" ]]; then
        ssh_args+=("--command=$cmd")
    fi
    
    gcloud compute ssh "${ssh_args[@]}"
}

# -----------------------------------------------------------------------------
# Cloud Build helpers
# -----------------------------------------------------------------------------
submit_build() {
    local config="$1"
    shift
    local substitutions="${1:-}"
    shift || true
    local extra_args=("$@")
    
    load_config
    
    local args=(
        "."
        "--config=$config"
        "--project=$PROJECT_ID"
    )
    
    if [[ -n "$substitutions" ]]; then
        args+=("--substitutions=$substitutions")
    fi
    
    # Add any extra args (--async, --region, etc.)
    args+=("${extra_args[@]}")
    
    gcloud builds submit "${args[@]}"
}

submit_build_async() {
    local config="$1"
    local substitutions="${2:-}"
    shift 2 || shift || true
    
    submit_build "$config" "$substitutions" --async "$@"
    
    echo ""
    info "Build submitted. Check status with:"
    echo "  make build-status TYPE=$(basename "$config" .yaml | sed 's/.*\///')"
}

# -----------------------------------------------------------------------------
# Print section header
# -----------------------------------------------------------------------------
header() {
    echo ""
    echo "=== $* ==="
}
