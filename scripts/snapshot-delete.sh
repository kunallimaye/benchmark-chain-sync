#!/usr/bin/env bash
# Delete a golden snapshot
source "$(dirname "$0")/common.sh"

SNAPSHOT="${1:-}"

load_config

if [[ -z "$SNAPSHOT" ]]; then
    error "SNAPSHOT is required"
    echo ""
    echo "Usage: $0 <snapshot-name>"
    echo ""
    echo "Available snapshots:"
    gcloud compute snapshots list \
        --project="$PROJECT_ID" \
        --filter="name~op-reth" \
        --format="value(name)" | sed 's/^/  /'
    exit 1
fi

header "Deleting Snapshot: $SNAPSHOT"

if [[ "$SNAPSHOT" == "$SNAPSHOT_NAME" ]]; then
    warn "This is the snapshot configured in config.toml!"
    warn "VMs will fail to provision without a valid snapshot."
    echo ""
fi

confirm "Are you sure you want to delete $SNAPSHOT?" || exit 0

gcloud compute snapshots delete "$SNAPSHOT" \
    --project="$PROJECT_ID" \
    --quiet

success "Snapshot deleted: $SNAPSHOT"
