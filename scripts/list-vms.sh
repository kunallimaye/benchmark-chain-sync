#!/usr/bin/env bash
# List VMs defined in config.toml
source "$(dirname "$0")/common.sh"

header "VMs in config.toml"

# Get VM details with defaults merged
cfg vm | jq -r '.[] | "  \(.name): \(.machine_type) / \(if .storage_type == "inbuilt-lssd" then "lssd" else .storage_type end) / TDX=\(.confidential_compute)"'
