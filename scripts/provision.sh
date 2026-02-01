#!/usr/bin/env bash
# Provision VMs from config.toml (Terraform)
source "$(dirname "$0")/common.sh"

VM="${1:-}"
WAIT="${2:-}"
PLAN_ONLY=""

# Check for --plan flag
for arg in "$@"; do
    if [[ "$arg" == "--plan" ]]; then
        PLAN_ONLY="true"
    fi
done

load_config

if [[ -n "$PLAN_ONLY" ]]; then
    header "Provisioning Plan (dry-run)"
else
    header "Provisioning Infrastructure"
fi

if [[ -n "$VM" ]]; then
    echo "VM Filter: $VM"
else
    echo "VMs: all from config.toml"
fi
echo ""

SUBSTITUTIONS="_GCS_BUCKET=$GCS_BUCKET,_VM=$VM"
if [[ -n "$PLAN_ONLY" ]]; then
    SUBSTITUTIONS="$SUBSTITUTIONS,_PLAN_ONLY=true"
fi

if [[ -n "$WAIT" && -z "$PLAN_ONLY" ]]; then
    # Synchronous mode
    submit_build "cloudbuild/benchmark/provision.yaml" "$SUBSTITUTIONS"
else
    # Async mode (default for provision, sync for plan)
    if [[ -n "$PLAN_ONLY" ]]; then
        submit_build "cloudbuild/benchmark/provision.yaml" "$SUBSTITUTIONS"
    else
        submit_build_async "cloudbuild/benchmark/provision.yaml" "$SUBSTITUTIONS"
    fi
fi
