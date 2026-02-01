#!/usr/bin/env bash
# Run benchmark on a VM
source "$(dirname "$0")/common.sh"

VM="${1:-}"

load_config

if [[ -z "$VM" ]]; then
    error "VM is required"
    echo ""
    echo "Usage: $0 <vm-name>"
    echo ""
    echo "Available VMs:"
    list_config_vms | sed 's/^/  /'
    exit 1
fi

header "Running benchmark on $VM"

submit_build "cloudbuild/benchmark/run.yaml" \
    "_VM=$VM,_GCS_BUCKET=$GCS_BUCKET" \
    "--region=$REGION"
