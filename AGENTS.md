# AGENTS.md - Coding Agent Guidelines

This document provides context for AI coding agents working in this repository.

## Project Overview

Benchmark infrastructure for comparing op-reth (Optimism's Reth execution client) performance on GCP. Uses Terraform for infrastructure, Ansible for configuration, and Cloud Build for CI/CD.

**Key Technologies:**
- Terraform 1.5+ (runs in Cloud Build, not locally)
- Ansible (runs in Cloud Build via cytopia/ansible image)
- Cloud Build (all operations run remotely)
- Python 3.11+ (for TOML parsing in Cloud Build)
- Make (orchestration)

## Quick Reference Commands

```bash
# Validate configuration
make validate-config          # Validate config.toml syntax
make validate-terraform       # Validate Terraform (requires local terraform)
make help                     # Show all available targets

# Build binaries
make build-reth               # Build op-reth binary
make build-op-node            # Build op-node binary (extract from Docker)

# Golden snapshot management
make list-snapshots           # List available golden snapshots
make create-snapshot VM=<name> # Create golden snapshot from synced VM
make delete-snapshot SNAPSHOT=<name>  # Delete old snapshot

# Provision and configure VMs
make provision                # Create all VMs from config.toml (disks from snapshot)
make provision VM=<name>      # Create specific VM
make configure                # Configure all VMs (LSSD: rsync from temp disk)
make configure VM=<name>      # Configure specific VM

# Status and monitoring
make status                   # Show builds, VMs, L1, snapshot status
make status-l1                # Check BNE node sync status
make list-vms                 # List VMs in config.toml
make list-instances           # List active Terraform-managed instances
make configure-status VM=<name>  # Check VM status
make build-status TYPE=<type> # Show status of any build type

# Cleanup
make cleanup                  # Destroy all VMs
make cleanup VM=<name>        # Destroy specific VM
```

## Configuration Files

### config.toml (main configuration)
```toml
[project]           # GCP project settings
[l1]                # L1 Ethereum endpoints (BNE)
[build]             # Build settings (reth_repo, reth_branch, op_node_version)
[tracing]           # OpenTelemetry tracing settings (Cloud Trace)
[snapshot]          # Golden snapshot settings (name, disk_size_gb)
[reth_config]       # Reth performance tuning (batch size, db settings)
[defaults.vm]       # Default VM settings (inherited by [[vm]] sections)
[[vm]]              # VM instance definitions (can have multiple)
```

**`[reth_config]` section:**
```toml
[reth_config]
batch_size = 10000              # Blocks per execution batch (default: 10000)
batch_duration = "1m"           # Max duration per batch (default: "1m")
db_max_size_gb = 15000          # Maximum database size in GB (default: 15000)
db_growth_step_mb = 4096        # Database growth increment in MB (default: 4096)
```

Lower batch sizes give better ETA visibility but ~7-15% slower sync. See `docs/PERFORMANCE-TUNING.md`.

### .env (secrets, gitignored)
```bash
L1_API_KEY=<your-bne-api-key>
```

## Architecture: Golden Snapshot Provisioning

VMs are provisioned from a golden snapshot (created from a fully synced VM):

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Golden Snapshot: op-reth-golden-YYYY-MM-DD-HH-MM          │
│                    Created from synced VM, ~5TB compressed                   │
└───────────────────────────────┬─────────────────────────────────────────────┘
                                │
              ┌─────────────────┼─────────────────────────────────┐
              │                 │                                 │
              ▼                 ▼                                 ▼
    ┌─────────────────┐   ┌─────────────────┐           ┌─────────────────┐
    │ pd-balanced     │   │ pd-ssd          │           │ LSSD machine    │
    │ Create disk     │   │ Create disk     │           │                 │
    │ from snapshot   │   │ from snapshot   │           │ 1. Create temp  │
    │ (~10-15 min)    │   │ (~10-15 min)    │           │    pd-balanced  │
    │                 │   │                 │           │    from snapshot│
    │ Data ready!     │   │ Data ready!     │           │ 2. Attach to VM │
    └─────────────────┘   └─────────────────┘           │ 3. rsync to LSSD│
                                                        │ 4. Delete temp  │
                                                        │ (~20-30 min)    │
                                                        └─────────────────┘
```

**Benefits:**
- Fast provisioning: ~15 min for persistent disks (vs ~6 hours for tar extraction)
- No download phase: snapshot lives in GCP, no GCS transfer
- Parallel: all VMs can provision simultaneously
- Easy to update: create new snapshot from any synced VM

## VM Storage Types

| Storage Type | Description | Use Case |
|--------------|-------------|----------|
| `pd-balanced` | General-purpose SSD | Default, good balance |
| `pd-ssd` | Higher IOPS SSD | Better random I/O |
| `hyperdisk-extreme` | Highest performance | Max IOPS/throughput, configurable |
| `lssd` (machine suffix) | Local NVMe RAID-0 | Lowest latency, no persistence |

**Hyperdisk requires provisioned IOPS and throughput:**
```toml
[[vm]]
name = "op-reth-hyperdisk"
storage_type = "hyperdisk-extreme"
provisioned_iops = 350000
provisioned_throughput = 5000  # MB/s
```

## Code Style Guidelines

### File Headers
All configuration files use this comment style:
```
# =============================================================================
# Title/Description
# =============================================================================
```

Subsections use:
```
# -----------------------------------------------------------------------------
# Subsection Title
# -----------------------------------------------------------------------------
```

### Terraform Conventions
- Use `snake_case` for resource names and variables
- Module structure: `terraform/modules/<name>/{main.tf,variables.tf,outputs.tf}`
- Always include `description` for variables
- Use `locals` block for computed values
- Labels should include: `project`, `managed-by`, resource-specific tags
- Use `prevent_destroy` lifecycle for critical data disks

### Ansible Conventions
- Roles in `ansible/roles/<name>/`
- Role structure: `tasks/main.yml`, `handlers/main.yml`, `defaults/main.yml`, `templates/`
- Use `{{ variable }}` Jinja2 syntax
- Task names should be descriptive sentences
- Use `notify` + handlers for service restarts

### Cloud Build YAML Conventions
- Step IDs use kebab-case: `'terraform-init'`, `'upload-to-gcs'`
- **CRITICAL: Escape shell variables with `$$`** to prevent Cloud Build interpretation:
  ```yaml
  # Wrong - Cloud Build will try to substitute $VARIABLE
  VARIABLE=$(command)
  
  # Correct - Shell variable preserved
  VARIABLE=$$(command)
  ```
- Cloud Build substitutions use `${_VAR}` format (underscore prefix)
- Only pass substitutions that are actually used in the template

### Makefile Conventions
- Targets use kebab-case: `create-l1`, `list-vms`
- Use `## Comment` after target for help text
- Load config from TOML: `$(shell grep ... config.toml | cut -d'"' -f2)`
- Use `-include .env` to load secrets

### Naming Conventions
- VM names: User-defined in `config.toml` `[[vm]]` `name` field
- GCP resources: `op-reth-*` prefix
- Service accounts: `op-reth-benchmark@<project>.iam.gserviceaccount.com`
- GCS paths: `gs://<bucket>/builds/`, `gs://<bucket>/terraform/`
- Golden snapshots: `op-reth-golden-YYYY-MM-DD-HH-MM`

## Error Handling

### Bash Scripts
```bash
set -euo pipefail    # Exit on error, undefined vars, pipe failures
```

### Terraform
- Use `depends_on` for resource ordering
- Use `count` or `for_each` for conditional resources
- Include `timeouts` block for long-running resources (like BNE)
- Use `prevent_destroy` lifecycle on data disks

### Ansible
- Use `ignore_errors: yes` sparingly, only for non-critical checks
- Use `changed_when: false` for read-only commands
- Use `register` + conditional `when` for idempotent operations
- Check for existing data before destructive operations

## Prerequisites for Development

### Cloud Build Service Account Permissions
The Cloud Build service account needs the following roles:

| Role | Purpose |
|------|---------|
| `roles/resourcemanager.projectIamAdmin` | Manage IAM bindings for benchmark VMs |
| `roles/servicenetworking.networksAdmin` | Create VPC peering for Cloud Build private pool |
| `roles/compute.osAdminLogin` | SSH to VMs via OS Login for Ansible configuration |

```bash
PROJECT_ID=your-project-id
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/resourcemanager.projectIamAdmin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/servicenetworking.networksAdmin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/compute.osAdminLogin"
```

### Manual IAM Setup (One-time)

The default Compute Engine service account needs permission to sign URLs for snapshot downloads.
This must be run manually by a project owner/admin:

```bash
PROJECT_ID=your-project-id
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

# Grant the default compute service account permission to sign URLs
gcloud iam service-accounts add-iam-policy-binding \
  ${PROJECT_NUMBER}-compute@developer.gserviceaccount.com \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/iam.serviceAccountTokenCreator" \
  --project=$PROJECT_ID
```

This allows the downloader VM to generate signed URLs for GCS objects during snapshot download.

### Local Requirements
- `gcloud` CLI configured with appropriate project
- `python3` with `tomllib` (Python 3.11+) for config validation
- `jq` for JSON parsing in status commands

## Important Gotchas

1. **No local Terraform** - All Terraform runs in Cloud Build. Use `make validate-terraform` only if you have terraform installed locally.

2. **Cloud Build substitution conflicts** - Any `$VAR` in shell scripts within Cloud Build YAML will be interpreted as a substitution. Always use `$$VAR` for shell variables.

3. **TOML defaults inheritance** - `[defaults.vm]` values are merged into `[[vm]]` sections during TOML-to-JSON conversion in Cloud Build.

4. **State stored in GCS** - Terraform state is in `gs://<bucket>/terraform/state/`. The `instances.json` tracks provisioned VMs.

5. **BNE sync time** - Blockchain Node Engine takes days to sync. The L1 node should only be created once.

6. **API key security** - `L1_API_KEY` should never be in config.toml or committed. Always use `.env` file.

7. **LSSD machine types** - Machines with `-lssd` suffix (e.g., `c3-standard-176-lssd`) have built-in NVMe SSDs. Storage is auto-configured as RAID-0. Do NOT specify `storage_type` or `disk_size_gb` for these machines.

8. **Golden snapshot required** - VMs are provisioned from a golden snapshot. Provisioning will fail if no valid snapshot is configured in `config.toml` `[snapshot]` section.

9. **Data disk protection** - Data disks have `prevent_destroy = true` in Terraform to prevent accidental deletion. To delete, you must modify the Terraform code.

10. **Hyperdisk provisioning** - Hyperdisk types require explicit `provisioned_iops` and `provisioned_throughput` settings.

11. **LSSD rsync** - LSSD machines can't create disks from snapshot directly (ephemeral NVMe). Cloud Build creates a temp disk from snapshot, attaches it, rsyncs data to LSSD RAID, then deletes the temp disk.

11. **PromQL label matching** - When combining metrics from different sources (e.g., `op_node_*` and `reth_*`), use `on(vm_name)` modifier for arithmetic operations. Labels must match explicitly or PromQL returns no data.
    ```promql
    # Wrong - label mismatch, returns no data
    op_node_metric - reth_metric
    
    # Correct - explicit label matching
    op_node_metric - on(vm_name) reth_metric
    ```

12. **Sync stages and dashboard** - The dashboard filters for `stage="Execution"`. When a VM is in other stages (StorageHashing, Merkle, etc.), throughput shows 0. This is normal - check VM logs to see actual stage.

13. **Targeted Terraform apply** - Use `_TARGET` substitution in provision.yaml to apply only specific modules:
    ```bash
    gcloud builds submit . --config=cloudbuild/provision.yaml \
      --substitutions="_TARGET=module.monitoring,..."
    ```
    Useful for dashboard updates without touching VMs, or avoiding `prevent_destroy` conflicts.

## Observability

### Metrics
Metrics are collected via Ops Agent and sent to GCP Managed Prometheus.
- op-reth: Scraped from `localhost:9001`
- op-node: Scraped from `localhost:7300`

Access metrics via Cloud Monitoring Metrics Explorer with PromQL queries.

### Tracing
OpenTelemetry traces are sent from op-reth to Cloud Trace via Ops Agent OTLP receiver.
- Configuration: `[tracing]` section in `config.toml`
- Default: 1% sampling, info level filter
- op-node does not support OTLP tracing

### Dashboard

A Cloud Monitoring dashboard is automatically provisioned via Terraform.
Access URL is output after `make provision`.

**Dashboard Layout:**
| Row | yPos | Height | Widget |
|-----|------|--------|--------|
| Row 1 | 0 | 8 | 4 Scorecards: L2 Tip, Chain Growth (min/avg/max) |
| Row 2 | 8 | 32 | 3 Tables: Throughput (blocks/s), Checkpoint, ETA (hours) |
| Row 3 | 40 | 12 | Execution Throughput (MGas/s) chart |
| Row 4 | 52 | 16 | Combined table (experimental) |

**Key PromQL Queries:**
```promql
# L2 Chain Tip
max(op_node_default_refs_number{layer="l2",type="l2_unsafe"})

# Chain Growth Rate
rate(op_node_default_refs_number{layer="l2",type="l2_unsafe"}[5m])

# Throughput (blocks/s per VM)
rate(reth_sync_checkpoint{stage="Execution"}[5m])

# Checkpoint (block # per VM)
reth_sync_checkpoint{stage="Execution"}

# ETA (hours per VM) - NOTE: requires on(vm_name) for label matching
(op_node_default_refs_number{layer="l2",type="l2_unsafe"} - on(vm_name) reth_sync_checkpoint{stage="Execution"}) / on(vm_name) (rate(reth_sync_checkpoint{stage="Execution"}[15m]) * 3600)

# Gas throughput (MGas/s per VM)
reth_sync_execution_gas_per_second / 1000000
```

**Table Widget Notes:**
- Tables use `timeSeriesTable` widget type
- `columnSettings` with `column = "vm_name"` displays VM names
- `tableTemplate = "{{vm_name}}"` does NOT work for row naming (known limitation)
- Each table should have a single `dataSet` for reliable rendering

### Performance Tuning
See `docs/PERFORMANCE-TUNING.md` for comprehensive guide on:
- Reth configuration (reth.toml) and CLI performance flags
- Batch size configuration (default 500K vs 20K for benchmarking)
- Linux system-level tuning (filesystem, I/O scheduler, sysctl)
- Bottleneck detection (CPU vs I/O, PromQL queries, Cloud Trace)
- Current infrastructure status (what's configured vs missing)

### ETA Calculation
See `docs/ETA-CALC.md` for comprehensive guide on:
- Calculating sync ETA for each pipeline stage
- Historical benchmark data (time per stage)
- PromQL queries for ETA calculation
- Reference processing rates by machine type

## File Structure

```
.
├── config.toml              # Main configuration (VMs, L1 endpoints, build settings)
├── .env                     # Secrets (L1_API_KEY, gitignored)
├── Makefile                 # Orchestration (all make targets)
├── AGENTS.md                # This file - developer/AI reference
├── README.md                # User-facing documentation
├── docs/
│   ├── PERFORMANCE-TUNING.md        # Comprehensive performance tuning guide
│   └── ETA-CALC.md                  # ETA calculation for sync stages
├── terraform/
│   ├── main.tf              # Root module
│   ├── variables.tf         # Input variables
│   ├── outputs.tf           # Outputs
│   └── modules/
│       ├── apis/            # GCP API enablement
│       ├── benchmark/       # VM + data disk (from snapshot)
│       ├── bne/             # Blockchain Node Engine (L1)
│       ├── cloudbuild-pool/ # Cloud Build private pool for SSH
│       ├── iam/             # Service accounts + IAM bindings
│       └── monitoring/      # Cloud Monitoring dashboard + Telemetry API
├── ansible/
│   ├── group_vars/          # Global variables (all.yml)
│   ├── playbooks/           # Ansible playbooks
│   │   ├── site.yml         # Full VM setup
│   │   ├── run-benchmark.yml
│   │   └── install-*.yml
│   └── roles/
│       ├── common/          # Base packages, user setup, gcloud CLI
│       ├── system_tuning/   # sysctl, I/O scheduler, THP, mount options
│       ├── ops_agent/       # GCP Ops Agent for metrics + OTLP traces
│       ├── op_reth/         # op-reth binary + systemd service + reth.toml
│       ├── op_node/         # op-node binary + systemd service
│       └── lssd_copy/       # rsync from temp disk to LSSD RAID
└── cloudbuild/              # Cloud Build configs
    ├── build-op-reth.yaml   # Build op-reth binary from source
    ├── build-op-node.yaml   # Build op-node binary (extract from Docker)
    ├── provision.yaml       # Terraform apply (create VMs)
    ├── configure.yaml       # Ansible playbook (configure VMs)
    ├── run-benchmark.yaml   # Run benchmark
    ├── cleanup.yaml         # Terraform destroy
    ├── create-l1.yaml       # Create BNE node
    └── destroy-l1.yaml      # Destroy BNE node
```
