#!/usr/bin/env bash
# Configure VMs with Ansible
source "$(dirname "$0")/common.sh"

VM="${1:-}"
WAIT="${2:-}"

load_config

header "Configuring VMs"

if [[ -n "$VM" ]]; then
    echo "VM: $VM"
else
    echo "VMs: all"
fi
echo ""

SUBSTITUTIONS="_VM=$VM,_GCS_BUCKET=$GCS_BUCKET"

if [[ -n "$WAIT" ]]; then
    # Synchronous mode
    submit_build "cloudbuild/benchmark/configure.yaml" "$SUBSTITUTIONS" "--region=$REGION"
else
    # Async mode (default)
    submit_build_async "cloudbuild/benchmark/configure.yaml" "$SUBSTITUTIONS" "--region=$REGION"
fi
