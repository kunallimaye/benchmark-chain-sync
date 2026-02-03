#!/usr/bin/env bash
# =============================================================================
# Status Commands
# =============================================================================
# Usage: status.sh {all|vm|sync|vms|instances} [options]
# =============================================================================
source "$(dirname "$0")/common.sh"

ACTION="${1:-all}"
shift || true
parse_flags "$@"

show_usage() {
    cat << 'EOF'
Usage: status.sh {all|vm|sync|vms|instances} [options]

Commands:
  all           Show overall status (builds, snapshots, VMs, L1)
  vm --vm=<n>   Show status for a specific VM
  sync          Show sync progress for all VMs (from logs)
  vms           List VMs defined in config.toml
  instances     List active instances in Terraform state

Options:
  --vm=<name>   VM name (for vm command)
EOF
    exit 1
}

load_config

case "$ACTION" in
    all)
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
        ;;
        
    vm)
        VM="${VM:-${POSITIONAL_ARGS[0]:-}}"
        
        if [[ -z "$VM" ]]; then
            error "VM is required"
            echo ""
            echo "Usage: status.sh vm --vm=<name>"
            echo ""
            echo "Available VMs:"
            list_config_vms | sed 's/^/  /'
            exit 1
        fi
        
        # Delegate to vm.sh status
        exec "$SCRIPTS_DIR/vm.sh" status --vm="$VM"
        ;;
        
    sync)
        # Delegate to vm.sh sync
        exec "$SCRIPTS_DIR/vm.sh" sync
        ;;
        
    vms)
        header "VMs in config.toml"
        cfg vm | jq -r '.[] | "  \(.name): \(.machine_type) / \(if .storage_type == "inbuilt-lssd" then "lssd" else .storage_type end) / TDX=\(.confidential_compute)"'
        ;;
        
    instances)
        header "Active Instances"
        gsutil cat "gs://$GCS_BUCKET/terraform/benchmark/terraform.tfstate" 2>/dev/null | \
            jq -r '.resources[] | select(.type == "google_compute_instance") | .instances[] | "  \(.attributes.name): \(.attributes.machine_type) / zone=\(.attributes.zone)"' 2>/dev/null || echo "  (none or state not accessible)"
        ;;
        
    *)
        error "Unknown action: $ACTION"
        show_usage
        ;;
esac
