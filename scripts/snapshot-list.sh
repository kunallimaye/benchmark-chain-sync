#!/usr/bin/env bash
# List golden snapshots
source "$(dirname "$0")/common.sh"

load_config

header "Golden Snapshots"

gcloud compute snapshots list \
    --project="$PROJECT_ID" \
    --filter="name~op-reth" \
    --format="table(name,status,diskSizeGb,creationTimestamp.date('%Y-%m-%d %H:%M'),description)" \
    2>/dev/null || echo "No snapshots found"

echo ""
echo "Current config.toml snapshot: $SNAPSHOT_NAME"
