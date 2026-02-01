#!/usr/bin/env bash
# Show overall status (builds, snapshots, VMs, L1)
source "$(dirname "$0")/common.sh"

load_config

header "Build Artifacts"
gsutil ls -l "gs://$GCS_BUCKET/builds/op-reth-*" 2>/dev/null | grep -v '.json$' | head -20 || echo "  No builds found"

header "Golden Snapshot"
if [[ -n "$SNAPSHOT_NAME" ]]; then
    gcloud compute snapshots describe "$SNAPSHOT_NAME" \
        --project="$PROJECT_ID" \
        --format="table(name,status,diskSizeGb,storageBytes.yesno(yes='size: ',no=''):label='')" \
        2>/dev/null || echo "  $SNAPSHOT_NAME (not found)"
else
    echo "  Not configured in config.toml"
fi

header "VMs in config.toml"
list_config_vms | sed 's/^/  /' || echo "  (none)"

header "Active Instances (Terraform state)"
gsutil cat "gs://$GCS_BUCKET/terraform/benchmark/terraform.tfstate" 2>/dev/null | \
    jq -r '.resources[] | select(.type == "google_compute_instance") | .instances[].attributes.name' 2>/dev/null | \
    sed 's/^/  /' || echo "  (none)"

header "L1 BNE Node"
gcloud alpha blockchain-node-engine nodes describe "l1-$L1_NETWORK" \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --format="value(state)" \
    2>/dev/null || echo "  Not found"
