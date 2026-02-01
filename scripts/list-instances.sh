#!/usr/bin/env bash
# List active instances from Terraform state
source "$(dirname "$0")/common.sh"

load_config

header "Active Instances"

# Try to read from terraform state in GCS
gsutil cat "gs://$GCS_BUCKET/terraform/benchmark/terraform.tfstate" 2>/dev/null | \
    jq -r '.resources[] | select(.type == "google_compute_instance") | .instances[] | "  \(.attributes.name): \(.attributes.machine_type) / zone=\(.attributes.zone)"' 2>/dev/null || echo "  (none or state not accessible)"
