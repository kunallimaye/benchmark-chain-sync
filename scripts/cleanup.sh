#!/usr/bin/env bash
# Destroy VMs
source "$(dirname "$0")/common.sh"

VM="${1:-}"

load_config

header "Destroying VMs"

if [[ -n "$VM" ]]; then
    echo "VM: $VM"
else
    echo "VMs: all"
    confirm "Are you sure you want to destroy ALL VMs?" || exit 0
fi
echo ""

submit_build "cloudbuild/benchmark/cleanup.yaml" \
    "_VM=$VM,_GCS_BUCKET=$GCS_BUCKET"
