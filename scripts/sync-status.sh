#!/usr/bin/env bash
# Show latest sync progress for each op-reth VM
source "$(dirname "$0")/common.sh"

load_config

header "Sync Status"

# Query logs and extract latest per VM
gcloud logging read '
resource.type="gce_instance"
textPayload=~"Committed stage progress"
' --project="$PROJECT_ID" --limit=50 --format=json 2>/dev/null | python3 -c "
import json, sys, re
from datetime import datetime

logs = json.load(sys.stdin)

if not logs:
    print('No sync progress logs found. VMs may not be syncing yet.')
    sys.exit(0)

# Group by VM and keep only the latest
latest_by_vm = {}
for log in logs:
    text = log.get('textPayload', '')
    vm_match = re.search(r'\+00:00 ([\w-]+) op-reth', text)
    if not vm_match:
        continue
    vm_name = vm_match.group(1)
    
    if vm_name not in latest_by_vm:
        latest_by_vm[vm_name] = log

# Parse and display as table
print(f\"{'VM':<40} {'Stage':<15} {'Pipeline':<9} {'Checkpoint':<11} {'Target':<11} {'Progress':<9} {'ETA':<8} {'Updated':<20}\")
print('-' * 130)

for vm_name in sorted(latest_by_vm.keys()):
    log = latest_by_vm[vm_name]
    text = log.get('textPayload', '')
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
"
