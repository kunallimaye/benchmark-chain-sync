#!/usr/bin/env bash
# Show status for a specific VM
source "$(dirname "$0")/common.sh"

VM="${1:-}"

load_config

if [[ -z "$VM" ]]; then
    error "VM is required"
    echo ""
    echo "Usage: $0 <vm-name>"
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
