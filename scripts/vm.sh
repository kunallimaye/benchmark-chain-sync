#!/usr/bin/env bash
# =============================================================================
# VM Management
# =============================================================================
# Usage: vm.sh {provision|configure|cleanup|benchmark|status|sync} [options]
# =============================================================================
source "$(dirname "$0")/common.sh"

ACTION="${1:-}"
shift || true
parse_flags "$@"

show_usage() {
    cat << 'EOF'
Usage: vm.sh {provision|configure|cleanup|benchmark|status|sync} [options]

Commands:
  provision   Create VMs from config.toml (Terraform)
  configure   Configure VMs with Ansible
  cleanup     Destroy VMs
  benchmark   Run benchmark on a VM
  status      Show status for a specific VM
  sync        Show sync progress for all VMs

Options:
  --vm=<name>   Target specific VM (optional for provision/configure/cleanup)
  --plan        Dry-run (show what would change, no apply)
  --force       Allow destructive changes (VM recreation / service restart)
  --wait        Wait for Cloud Build to complete

Examples:
  vm.sh provision --plan              # Preview Terraform changes
  vm.sh provision                     # Apply (blocks if VMs would be recreated)
  vm.sh provision --force             # Force apply (allows recreation)
  vm.sh configure --vm=my-vm --force  # Reconfigure and restart services
EOF
    exit 1
}

[[ -z "$ACTION" ]] && show_usage

load_config

case "$ACTION" in
    provision)
        if [[ -n "$PLAN_ONLY" ]]; then
            header "Provisioning Plan (dry-run)"
        else
            header "Provisioning VMs"
        fi
        
        if [[ -n "$VM" ]]; then
            echo "VM: $VM"
        else
            echo "VMs: all from config.toml"
        fi
        [[ -n "$FORCE" ]] && echo "Mode: FORCE (allows VM recreation)"
        echo ""
        
        SUBSTITUTIONS="_GCS_BUCKET=$GCS_BUCKET,_VM=$VM,_L1_API_KEY=$L1_API_KEY"
        [[ -n "$PLAN_ONLY" ]] && SUBSTITUTIONS="$SUBSTITUTIONS,_PLAN_ONLY=true"
        [[ -n "$FORCE" ]] && SUBSTITUTIONS="$SUBSTITUTIONS,_FORCE=true"
        
        if [[ -n "$WAIT" ]] || [[ -n "$PLAN_ONLY" ]]; then
            submit_build "cloudbuild/benchmark/provision.yaml" "$SUBSTITUTIONS"
        else
            submit_build_async "cloudbuild/benchmark/provision.yaml" "$SUBSTITUTIONS"
        fi
        ;;
        
    configure)
        if [[ -n "$PLAN_ONLY" ]]; then
            header "Configure Plan (dry-run)"
        else
            header "Configuring VMs"
        fi
        
        if [[ -n "$VM" ]]; then
            echo "VM: $VM"
        else
            echo "VMs: all"
        fi
        [[ -n "$FORCE" ]] && echo "Mode: FORCE (will restart services if config changed)"
        echo ""
        
        SUBSTITUTIONS="_VM=$VM,_GCS_BUCKET=$GCS_BUCKET,_FORCE=$FORCE,_PLAN_ONLY=$PLAN_ONLY"
        
        if [[ -n "$WAIT" ]]; then
            submit_build "cloudbuild/benchmark/configure.yaml" "$SUBSTITUTIONS" "--region=$REGION"
        else
            submit_build_async "cloudbuild/benchmark/configure.yaml" "$SUBSTITUTIONS" "--region=$REGION"
        fi
        ;;
        
    cleanup)
        header "Destroying VMs"
        
        if [[ -n "$VM" ]]; then
            echo "VM: $VM"
        else
            echo "VMs: all"
            confirm "Are you sure you want to destroy ALL VMs?" || exit 0
        fi
        echo ""
        
        submit_build "cloudbuild/benchmark/cleanup.yaml" "_VM=$VM,_GCS_BUCKET=$GCS_BUCKET"
        ;;
        
    benchmark)
        VM="${VM:-${POSITIONAL_ARGS[0]:-}}"
        require_var VM "vm.sh benchmark --vm=<name>"
        
        header "Running Benchmark on $VM"
        submit_build "cloudbuild/benchmark/run.yaml" "_VM=$VM,_GCS_BUCKET=$GCS_BUCKET" "--region=$REGION"
        ;;
        
    status)
        VM="${VM:-${POSITIONAL_ARGS[0]:-}}"
        
        if [[ -z "$VM" ]]; then
            error "VM is required"
            echo ""
            echo "Usage: vm.sh status --vm=<name>"
            echo ""
            echo "Available VMs:"
            list_config_vms | sed 's/^/  /'
            exit 1
        fi
        
        header "Status for $VM"
        
        # SSH to VM and run status commands
        gcloud compute ssh "$VM" \
            --zone="$ZONE" \
            --project="$PROJECT_ID" \
            --ssh-flag="-o Hostname=nic0.$VM.$ZONE.c.$PROJECT_ID.internal.gcpnode.com" \
            --command='
echo ""
echo "=== Services ==="
systemctl is-active op-reth.service 2>/dev/null && echo "op-reth: RUNNING" || echo "op-reth: not running"
systemctl is-active op-node.service 2>/dev/null && echo "op-node: RUNNING" || echo "op-node: not running"

echo ""
echo "=== Data Directory ==="
if [ -f /mnt/data/op-reth/db/mdbx.dat ]; then
    echo "Database exists"
    du -sh /mnt/data/op-reth/db 2>/dev/null || true
else
    echo "Database not found"
fi

echo ""
echo "=== Disk Usage ==="
df -h /mnt/data 2>/dev/null || echo "Data disk not mounted"

echo ""
echo "=== Recent Logs (op-reth) ==="
journalctl -u op-reth.service -n 10 --no-pager 2>/dev/null || echo "No logs available"
' 2>/dev/null || error "Could not SSH to $VM. VM may not exist or SSH may not be ready."
        ;;
        
    sync)
        header "Sync Status"
        
        # Query sync progress logs (Committed stage progress) and synced logs (Inserted new L2 unsafe block)
        # Use jsonPayload.message since Ops Agent sends structured logs
        {
            gcloud logging read '
resource.type="gce_instance"
jsonPayload.message=~"Committed stage progress"
' --project="$PROJECT_ID" --limit=50 --format=json 2>/dev/null
            
            gcloud logging read '
resource.type="gce_instance"
jsonPayload.message=~"Inserted new L2 unsafe block"
' --project="$PROJECT_ID" --limit=20 --format=json 2>/dev/null
        } | python3 -c "
import json, sys, re
from datetime import datetime

# Read all JSON arrays from stdin and merge them
all_logs = []
buffer = ''
for line in sys.stdin:
    buffer += line
    if line.strip() == ']':
        try:
            all_logs.extend(json.loads(buffer))
        except:
            pass
        buffer = ''

if not all_logs:
    print('No sync progress logs found. VMs may not be syncing yet.')
    sys.exit(0)

# Group by VM and keep only the latest
latest_by_vm = {}
synced_vms = {}  # VMs that are synced (processing live blocks)

for log in all_logs:
    # Get VM name from label (more reliable than parsing text)
    vm_name = log.get('labels', {}).get('compute.googleapis.com/resource_name', '')
    if not vm_name:
        continue
    
    # Get message from jsonPayload
    text = log.get('jsonPayload', {}).get('message', '')
    if not text:
        continue
    
    # Check if this is a synced VM (op-node inserting live blocks)
    if 'Inserted new L2 unsafe block' in text:
        if vm_name not in synced_vms:
            synced_vms[vm_name] = log
        continue
    
    # Otherwise it's a sync progress log
    if vm_name not in latest_by_vm:
        latest_by_vm[vm_name] = log

# Parse and display as table
print(f\"{'VM':<40} {'Stage':<15} {'Pipeline':<9} {'Checkpoint':<11} {'Target':<11} {'Progress':<9} {'ETA':<8} {'Updated':<20}\")
print('-' * 130)

# Show syncing VMs first
for vm_name in sorted(latest_by_vm.keys()):
    log = latest_by_vm[vm_name]
    text = log.get('jsonPayload', {}).get('message', '')
    timestamp_str = log.get('timestamp', '')
    
    # Parse timestamp and convert to local timezone
    try:
        ts = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
        local_ts = ts.astimezone().strftime('%Y-%m-%d %H:%M:%S')
    except:
        local_ts = '-'
    
    stage = re.search(r'stage=(\w+)', text)
    pipeline = re.search(r'pipeline_stages=(\d+/\d+)', text)
    checkpoint = re.search(r'checkpoint=(\d+)', text)
    target = re.search(r'target=(\d+)', text)
    progress = re.search(r'stage_progress=([\d.]+)', text)
    eta = re.search(r'stage_eta=([\dhms]+)', text)
    
    print(f\"{vm_name:<40} {(stage.group(1) if stage else '-'):<15} {(pipeline.group(1) if pipeline else '-'):<9} {(checkpoint.group(1) if checkpoint else '-'):<11} {(target.group(1) if target else '-'):<11} {((progress.group(1) + '%') if progress else '-'):<9} {(eta.group(1) if eta else '-'):<8} {local_ts:<20}\")

# Show synced VMs
for vm_name in sorted(synced_vms.keys()):
    if vm_name in latest_by_vm:
        continue  # Already shown above with sync progress
    log = synced_vms[vm_name]
    text = log.get('jsonPayload', {}).get('message', '')
    timestamp_str = log.get('timestamp', '')
    
    try:
        ts = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
        local_ts = ts.astimezone().strftime('%Y-%m-%d %H:%M:%S')
    except:
        local_ts = '-'
    
    # Extract block number from op-node log
    block_match = re.search(r'number=(\d+)', text)
    block_num = block_match.group(1) if block_match else '-'
    
    print(f\"{vm_name:<40} {'SYNCED':<15} {'-':<9} {block_num:<11} {block_num:<11} {'100%':<9} {'-':<8} {local_ts:<20}\")
"
        ;;
        
    *)
        error "Unknown action: $ACTION"
        show_usage
        ;;
esac
