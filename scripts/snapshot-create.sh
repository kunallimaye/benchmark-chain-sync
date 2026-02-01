#!/usr/bin/env bash
# Create golden snapshot from a running VM
source "$(dirname "$0")/common.sh"

VM="${1:-}"

load_config

if [[ -z "$VM" ]]; then
    error "VM is required"
    echo ""
    echo "Usage: $0 <vm-name>"
    echo ""
    echo "This will:"
    echo "  1. Stop op-reth on the VM (briefly)"
    echo "  2. Create a snapshot of the data disk"
    echo "  3. Restart op-reth"
    echo ""
    echo "Available VMs:"
    gcloud compute instances list \
        --project="$PROJECT_ID" \
        --filter="name~op-reth" \
        --format="value(name)" | sed 's/^/  /'
    exit 1
fi

header "Creating Golden Snapshot from $VM"

DISK_NAME="${VM}-data"
NEW_SNAPSHOT_NAME="op-reth-golden-$(date +%Y-%m-%d-%H-%M)"

echo "Source disk:    $DISK_NAME"
echo "Snapshot name:  $NEW_SNAPSHOT_NAME"
echo ""

confirm "This will briefly stop op-reth. Continue?" || exit 0

echo ""
info "Stopping op-reth..."
gcloud compute ssh "$VM" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --command="sudo systemctl stop op-reth op-node" 2>/dev/null || true

info "Creating snapshot..."
gcloud compute snapshots create "$NEW_SNAPSHOT_NAME" \
    --source-disk="$DISK_NAME" \
    --source-disk-zone="$ZONE" \
    --project="$PROJECT_ID" \
    --description="Golden snapshot from $VM at $(date -Iseconds)"

info "Restarting op-reth..."
gcloud compute ssh "$VM" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --command="sudo systemctl start op-reth op-node" 2>/dev/null || true

echo ""
success "Snapshot created: $NEW_SNAPSHOT_NAME"
echo ""
echo "Update config.toml [snapshot] section:"
echo "  name = \"$NEW_SNAPSHOT_NAME\""
