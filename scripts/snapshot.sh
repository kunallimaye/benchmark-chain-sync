#!/usr/bin/env bash
# =============================================================================
# Snapshot Management
# =============================================================================
# Usage: snapshot.sh {create|delete|list} [options]
# =============================================================================
source "$(dirname "$0")/common.sh"

ACTION="${1:-}"
shift || true
parse_flags "$@"

show_usage() {
    cat << 'EOF'
Usage: snapshot.sh {create|delete|list} [options]

Commands:
  create --vm=<name>        Create golden snapshot from a running VM
  delete --snapshot=<name>  Delete a golden snapshot
  list                      List all golden snapshots

Options:
  --vm=<name>        VM name (for create)
  --snapshot=<name>  Snapshot name (for delete)
EOF
    exit 1
}

[[ -z "$ACTION" ]] && show_usage

load_config

case "$ACTION" in
    create)
        # Get VM from flag or positional arg
        VM="${VM:-${POSITIONAL_ARGS[0]:-}}"
        
        if [[ -z "$VM" ]]; then
            error "VM is required"
            echo ""
            echo "Usage: snapshot.sh create --vm=<name>"
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
        ;;
        
    delete)
        # Get snapshot from flag or positional arg
        SNAPSHOT="${SNAPSHOT:-${POSITIONAL_ARGS[0]:-}}"
        
        if [[ -z "$SNAPSHOT" ]]; then
            error "SNAPSHOT is required"
            echo ""
            echo "Usage: snapshot.sh delete --snapshot=<name>"
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
        ;;
        
    list)
        header "Golden Snapshots"
        
        gcloud compute snapshots list \
            --project="$PROJECT_ID" \
            --filter="name~op-reth" \
            --format="table(name,status,diskSizeGb,creationTimestamp.date('%Y-%m-%d %H:%M'),description)" \
            2>/dev/null || echo "No snapshots found"
        
        echo ""
        echo "Current config.toml snapshot: $SNAPSHOT_NAME"
        ;;
        
    *)
        error "Unknown action: $ACTION"
        show_usage
        ;;
esac
