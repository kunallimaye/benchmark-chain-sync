#!/usr/bin/env bash
# Show help text
source "$(dirname "$0")/common.sh"

cat << 'EOF'
op-reth Base Benchmark

Usage: make [target] [VAR=value ...]

Targets:
  L1 Infrastructure:
    l1-create             Create L1 BNE node (takes days to sync!)
    l1-destroy            Destroy L1 infrastructure (WARNING: re-sync takes days!)
    l1-status             Check BNE node sync status and endpoints

  Build Binaries:
    build-reth            Build op-reth binary from source
    build-op-node         Build op-node binary (extract from Docker)
    build-status          Show build status (requires TYPE=...)

  Snapshot Management:
    snapshot-create       Create golden snapshot from running VM (requires VM=name)
    snapshot-list         List golden snapshots
    snapshot-delete       Delete a golden snapshot (requires SNAPSHOT=name)

  VM Management:
    provision             Create VMs from config.toml
    provision-plan        Preview what Terraform would change (dry-run)
    configure             Configure VMs with Ansible
    configure-plan        Preview what Ansible would change (dry-run)
    cleanup               Destroy VMs
    benchmark             Run benchmark on VM (requires VM=name)

  Status & Monitoring:
    status                Show overall status (builds, snapshots, VMs, L1)
    status-vm             Show status for a specific VM (requires VM=name)
    sync-status           Show sync progress for all VMs (from logs)
    list-vms              List VMs defined in config.toml
    list-instances        List active instances in Terraform state

  Apply Infrastructure:
    apply-foundation      Apply foundation infrastructure (APIs, IAM, Pool)
    apply-monitoring      Apply monitoring infrastructure (dashboards, metrics)

  Utilities:
    validate-config       Validate config.toml syntax
    validate-terraform    Validate Terraform configuration
    help                  Show this help

Variables:
  VM=<name>        Target specific VM (optional for provision/configure/cleanup)
  SNAPSHOT=<name>  Snapshot name (required for snapshot-delete)
  TYPE=<type>      Build type for build-status (configure|provision|benchmark|...)
  WAIT=1           Wait for Cloud Build to complete (synchronous)
  FORCE=true       Allow destructive changes (VM recreation / service restart)
  RETH_COMMIT=<sha> Override git commit for build-reth

Safety Features:
  The provision and configure commands have built-in safety checks:
  
  provision:
    - Runs 'terraform plan' first to detect changes
    - BLOCKS if any VM would be recreated (prevents data loss on LSSD)
    - Use FORCE=true to allow VM recreation
  
  configure:
    - Checks if services are already running
    - FAILS if config changes would affect running services
    - Use FORCE=true to allow service restarts

Examples:
  # Safe provisioning workflow
  make provision-plan              # Preview Terraform changes
  make provision                   # Apply (blocks if VMs would be recreated)
  make provision FORCE=true        # Force apply (allows VM recreation)
  
  # Safe configuration workflow
  make configure-plan              # Preview Ansible changes
  make configure                   # Apply (fails if running services affected)
  make configure FORCE=true        # Force apply (restarts services)
  
  # Target specific VM
  make provision VM=my-vm
  make configure VM=my-vm FORCE=true
  make cleanup VM=my-vm

Full Workflow (with golden snapshot):
  1. make l1-create                 # Create L1 node (one-time, takes days)
  2. Create API key in GCP Console, add to .env
  3. make build-reth && make build-op-node
  4. Sync a VM to desired block height (manual)
  5. make snapshot-create VM=<name> # Create golden snapshot
  6. Edit config.toml: set [snapshot] name and [[vm]] sections
  7. make provision                 # Create VMs (disks from snapshot)
  8. make configure                 # Configure VMs
  9. make status                    # Check overall status
  10. make cleanup                  # Destroy VMs when done

Aliases (backwards compatible):
  create-l1 -> l1-create
  destroy-l1 -> l1-destroy
  status-l1 -> l1-status
  create-snapshot -> snapshot-create
  delete-snapshot -> snapshot-delete
  list-snapshots -> snapshot-list
  configure-status -> status-vm
EOF
