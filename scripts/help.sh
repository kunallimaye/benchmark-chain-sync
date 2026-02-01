#!/usr/bin/env bash
# Show help text
source "$(dirname "$0")/common.sh"

cat << 'EOF'
op-reth Base Benchmark

Usage: make [target] [VAR=value ...]

Targets:
  L1 Infrastructure:
    create-l1             Create L1 BNE node (takes days to sync!)
    destroy-l1            Destroy L1 infrastructure (WARNING: re-sync takes days!)
    status-l1             Check BNE node sync status and endpoints

  Build Binaries:
    build-reth            Build op-reth binary from source
    build-op-node         Build op-node binary (extract from Docker)

  Snapshot Management:
    create-snapshot       Create golden snapshot from running VM (requires VM=name)
    list-snapshots        List golden snapshots
    delete-snapshot       Delete a golden snapshot (requires SNAPSHOT=name)

  Benchmark Infrastructure:
    provision             Create VMs from config.toml (all VMs, or VM=name)
    provision-plan        Dry-run provision (terraform plan, no apply)
    configure             Configure VMs with Ansible (all VMs, or VM=name)
    benchmark             Run benchmark on VM (requires VM=name)
    cleanup               Destroy VMs (all VMs, or VM=name)

  Status & Monitoring:
    status                Show current build artifacts and infrastructure
    configure-status      Show configure/sync status for a VM (requires VM=name)
    build-status          Show status of most recent build (requires TYPE=...)
    benchmark-status      Show status of most recent benchmark build
    list-vms              List VMs defined in config.toml
    list-instances        List active instances in Terraform state

  Foundation:
    apply-foundation      Apply foundation infrastructure (APIs, IAM, Pool)
    apply-monitoring      Apply monitoring infrastructure (dashboards, metrics)

  Utilities:
    validate-config       Validate config.toml syntax
    help                  Show this help

Configuration:
  Edit config.toml for project, L1, and VM configuration
  Create .env with L1_API_KEY (see .env.example)

Variables:
  VM             Filter to specific VM name (optional)
  SNAPSHOT       Snapshot name for delete-snapshot (required)
  TYPE           Build type for build-status (configure|provision|benchmark|...)
  WAIT           Wait for build to complete (set to any value)
  RETH_COMMIT    Override git commit for build (optional)

Workflow (with golden snapshot):
  1. make create-l1                    # Create L1 node (one-time, takes days)
  2. Create API key in GCP Console, add to .env
  3. make build-reth && make build-op-node
  4. Sync a VM to desired block height (manual)
  5. make create-snapshot VM=<name>    # Create golden snapshot
  6. Edit config.toml: set [snapshot] name and [[vm]] sections
  7. make provision                    # Create VMs (disks from snapshot)
  8. make configure                    # Configure VMs (LSSD: rsync from temp disk)
  9. make benchmark VM=<name>          # Run benchmark
  10. make cleanup                     # Destroy VMs

Golden Snapshot Management:
  make list-snapshots                  # List available golden snapshots
  make create-snapshot VM=<name>       # Create new snapshot from synced VM
  make delete-snapshot SNAPSHOT=<name> # Delete old snapshot

Single VM operations:
  make provision VM=<name>             # Create specific VM
  make configure VM=<name>             # Configure specific VM
  make configure-status VM=<name>      # Check VM status
  make cleanup VM=<name>               # Destroy specific VM
EOF
