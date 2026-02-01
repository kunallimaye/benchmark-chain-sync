# op-reth Base Benchmark

Benchmark op-reth sync performance on Base L2 network.

## Overview

Infrastructure-as-code for benchmarking op-reth performance on GCP:

| Component | Technology | Purpose |
|-----------|------------|---------|
| Infrastructure | Terraform | GCE VMs, disks, IAM, Dashboard |
| Configuration | Ansible | Install op-reth, op-node, Ops Agent |
| CI/CD | Cloud Build | Build binaries, provision/configure VMs |
| Metrics | GCP Managed Prometheus | Collect and query metrics |
| Tracing | Cloud Trace | Distributed tracing via OTLP |
| Dashboard | Cloud Monitoring | Visualize key performance metrics |
| Orchestration | Makefile | Manual triggering |

## Architecture

VMs are provisioned from a **golden snapshot** containing a synced op-reth database:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Golden Snapshot: op-reth-pruned-2026-01-31               │
│                    Created from synced VM, ~1.4TB compressed                │
└───────────────────────────────┬─────────────────────────────────────────────┘
                                │
              ┌─────────────────┼─────────────────────────────────┐
              │                 │                                 │
              ▼                 ▼                                 ▼
    ┌─────────────────┐   ┌─────────────────┐           ┌─────────────────┐
    │ pd-balanced     │   │ pd-ssd          │           │ LSSD machine    │
    │ Create disk     │   │ Create disk     │           │                 │
    │ from snapshot   │   │ from snapshot   │           │ 1. Create temp  │
    │ (~10-15 min)    │   │ (~10-15 min)    │           │    disk from    │
    │                 │   │                 │           │    snapshot     │
    │ Data ready!     │   │ Data ready!     │           │ 2. rsync to LSSD│
    └─────┬───────────┘   └─────┬───────────┘           │ 3. Delete temp  │
          │                     │                       └─────┬───────────┘
          │                     │                             │
          └─────────────────────┴──────┬──────────────────────┘
                                       ▼
                             ┌─────────────────┐
                             │  BNE (L1 Node)  │
                             │  - JSON-RPC     │
                             │  - Beacon API   │
                             └─────────────────┘
```

## Prerequisites

- GCP project with required APIs enabled
- `gcloud` CLI configured with project access
- Golden snapshot available (see `make list-snapshots`)

**For detailed setup instructions (Cloud Build permissions, Manual IAM setup), see [AGENTS.md](AGENTS.md#prerequisites-for-development).**

## Quick Start

### 1. One-Time Setup

```bash
# Create L1 BNE node (takes days to sync!)
make create-l1

# After BNE syncs, create API key in GCP Console
# APIs & Services > Credentials > Create API Key
echo "L1_API_KEY=your-api-key" > .env

# Build binaries
make build-reth
make build-op-node
```

### 2. Configure VMs

Edit `config.toml`:

```toml
[project]
project_id = "your-project-id"
chain_network = "base-mainnet"  # Blockchain network name

[snapshot]
name = "op-reth-pruned-2026-01-31"  # Golden snapshot to use
disk_size_gb = 3000

[[vm]]
name = "my-benchmark-vm"
machine_type = "c3-standard-44"
storage_type = "pd-ssd"
disk_size_gb = 3000
confidential_compute = true  # Enable TDX
```

### 3. Provision and Configure

```bash
# Create VMs (creates disks from snapshot, auto-generates inventory)
make provision

# Configure VMs (installs binaries, starts services)
make configure

# Check overall status
make status
```

### 4. Monitor Progress

```bash
# SSH to a specific VM
gcloud compute ssh VM_NAME --project=PROJECT --zone=ZONE -- \
  -o Hostname=nic0.VM_NAME.ZONE.c.PROJECT.internal.gcpnode.com

# On the VM: check services
sudo systemctl status op-reth op-node
sudo journalctl -u op-reth -n 20
```

**Dashboard:** https://console.cloud.google.com/monitoring/dashboards?project=YOUR_PROJECT

### 5. Cleanup

```bash
make cleanup              # Destroy all VMs
make cleanup VM=<name>    # Destroy specific VM
```

## Configuration

### config.toml

```toml
[project]
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"
network = "default"              # GCP VPC network
chain_network = "base-mainnet"   # Blockchain network (base-mainnet or base-sepolia)
gcs_bucket = "base-mainnet-snapshot"

[l1]
rpc_endpoint = "https://json-rpc.xxx.blockchainnodeengine.com"
beacon_endpoint = "https://beacon.xxx.blockchainnodeengine.com"

[build]
reth_repo = "https://github.com/paradigmxyz/reth.git"
reth_branch = "main"
op_node_version = "v1.16.5"

[snapshot]
name = "op-reth-pruned-2026-01-31"  # Golden snapshot name
disk_size_gb = 3000                  # Target disk size for new VMs

[defaults.vm]
disk_size_gb = 3000
machine_type = "c3-standard-44"
storage_type = "pd-balanced"
confidential_compute = true          # Enable TDX
node_mode = "full"                   # "full" (pruned) or "archive"
engine_cache_mb = 16384              # Cross-block cache size
engine_workers = 44                  # State root workers (match vCPU count)

[[vm]]
name = "op-reth-c3-standard-44-pdssd"
storage_type = "pd-ssd"

[[vm]]
name = "op-reth-c3-standard-44-lssd"
machine_type = "c3-standard-44-lssd"  # LSSD suffix = built-in NVMe
storage_type = "inbuilt-lssd"         # Built-in NVMe, no disk_size_gb needed
```

### .env (secrets, gitignored)

```bash
L1_API_KEY=your-bne-api-key
```

## Make Targets

```bash
make help                        # Show all targets

# L1 Infrastructure
make create-l1                   # Create BNE node (one-time)
make status-l1                   # Check BNE sync status
make destroy-l1                  # Destroy BNE node

# Build
make build-reth                  # Build op-reth binary
make build-op-node               # Build op-node (extract from Docker)

# Golden Snapshot Management
make list-snapshots              # List available golden snapshots
make create-snapshot VM=<name>   # Create snapshot from synced VM
make delete-snapshot SNAPSHOT=<name>  # Delete old snapshot

# Provision & Configure
make provision                   # Create all VMs (+ auto-generate inventory)
make provision VM=<name>         # Create specific VM
make configure                   # Configure all VMs (install binaries, start services)
make configure VM=<name>         # Configure specific VM

# Status & Monitoring
make status                      # Show builds, VMs, L1, snapshot status
make sync-status                 # Show latest sync progress for each VM (from logs)
make list-vms                    # List VMs in config.toml
make list-instances              # List active Terraform instances
make configure-status VM=<name>  # Check VM configuration status

# Benchmark
make benchmark VM=<name>         # Run benchmark on VM

# Cleanup
make cleanup                     # Destroy all VMs
make cleanup VM=<name>           # Destroy specific VM
```

## Golden Snapshot Workflow

VMs are provisioned from a **golden snapshot** - a GCP disk snapshot containing a synced op-reth database.

### How It Works

**For persistent disk VMs (pd-balanced, pd-ssd, hyperdisk):**
- Disk is created directly from snapshot (~10-15 min)
- Data is immediately available when VM starts

**For LSSD machines (NVMe):**
- Ephemeral NVMe cannot be created from snapshot
- Cloud Build creates a temp pd-balanced disk from snapshot
- Ansible rsyncs data from temp disk to LSSD RAID (~20-30 min)
- Temp disk is automatically deleted

### Benefits
- Fast provisioning: ~15 min for persistent disks
- No download phase: snapshot lives in GCP
- Parallel: all VMs provision simultaneously
- Easy updates: create new snapshot from any synced VM

### Snapshot Management

```bash
# List available snapshots
make list-snapshots

# Create new snapshot from a synced VM
make create-snapshot VM=op-reth-synced-vm

# Delete old snapshot
make delete-snapshot SNAPSHOT=op-reth-golden-old
```

## VM Types

The infrastructure supports various storage types for benchmarking:

| Storage Type | TDX | Description |
|--------------|-----|-------------|
| `pd-balanced` | Yes/No | General-purpose SSD (default) |
| `pd-ssd` | Yes/No | Higher IOPS SSD |
| `hyperdisk-extreme` | Yes/No | Highest performance (350K IOPS, 5GB/s) |
| `inbuilt-lssd` | Yes/No | Built-in NVMe RAID-0 (for -lssd and -metal machine types) |

## Observability

### Metrics

Metrics are collected via GCP Managed Prometheus:

| Label | Description |
|-------|-------------|
| `reth_version` | Git commit hash |
| `run_id` | Unique benchmark run ID |
| `network` | base-mainnet or base-sepolia |
| `vm_name` | Full VM name |
| `machine_type` | GCE machine type |
| `storage_type` | Disk type |

Query in Cloud Monitoring:
```
prometheus.googleapis.com/reth_*/gauge{reth_version="6df249c"}
```

### Tracing

OpenTelemetry traces are sent from op-reth to Cloud Trace (1% sampling by default).

Configure in `config.toml`:
```toml
[tracing]
enabled = true
sample_ratio = 0.01     # 1% of traces
filter = "info"         # trace, debug, info, warn, error
```

### Dashboard

A Cloud Monitoring dashboard is automatically provisioned with key metrics:

**Layout:**
| Row | Widget | Description |
|-----|--------|-------------|
| Row 1 | 4 Scorecards | L2 Tip, Chain Growth (min/avg/max blocks/s) |
| Row 2 | 3 Tables | Throughput (blocks/s), Checkpoint, ETA (hours) per VM |
| Row 3 | Chart | Execution Throughput (MGas/s) over time |
| Row 4 | Table | Combined table (experimental) |

**Key Metrics:**
- **Throughput** - Blocks processed per second per VM
- **Checkpoint** - Current block number per VM
- **ETA** - Hours remaining to sync per VM
- **MGas/s** - Gas throughput (actual work done)

**Note:** Dashboard filters for `stage="Execution"`. When a VM is in other stages (StorageHashing, Merkle), throughput shows 0. This is normal - check VM logs to see actual stage.

### Access Points

| Resource | URL |
|----------|-----|
| **Dashboard** | https://console.cloud.google.com/monitoring/dashboards?project=bct-prod-c3-tdx-3 |
| **Cloud Trace** | https://console.cloud.google.com/traces/list?project=bct-prod-c3-tdx-3 |
| **Metrics Explorer** | https://console.cloud.google.com/monitoring/metrics-explorer?project=bct-prod-c3-tdx-3 |
| **Cloud Logging** | https://console.cloud.google.com/logs/query?project=bct-prod-c3-tdx-3 |

### Bottleneck Detection

See [docs/BOTTLENECK-DETECTION.md](docs/BOTTLENECK-DETECTION.md) for:
- Identifying CPU vs I/O bottlenecks
- Key PromQL queries
- Using Cloud Trace for deep-dive analysis
- Troubleshooting guide

## Troubleshooting

### View Cloud Build Logs

```bash
# List recent builds
gcloud builds list --project=your-project-id --limit=5

# Stream logs for running build
gcloud builds log BUILD_ID --project=your-project-id --stream

# View configure build status
make build-status TYPE=configure
```

### SSH to VM

```bash
gcloud compute ssh <vm-name> \
  --zone=us-central1-a \
  --project=your-project-id
```

### Check Service Status

```bash
# On the VM
sudo systemctl status op-reth
sudo systemctl status op-node
sudo systemctl status snapshot-extract
sudo journalctl -u op-reth -f
```

### Query Sync Status

```bash
curl -s http://localhost:8545 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'
```

### Common Issues

| Issue | Solution |
|-------|----------|
| `make provision` fails with IAM error | Run manual IAM setup (see [AGENTS.md](AGENTS.md#manual-iam-setup-one-time)) |
| Download disk not found | Run `make create-download-disk` first |
| Snapshot file not found | Run `make download` to download snapshot |
| Extraction stuck | Check `/mnt/data/.extract-status` for errors |
| Services not starting | Wait for `stage: ready` in status file |
| Cloud Build timeout | Check `make configure-status VM=<name>` - extraction continues on VM |
| Dashboard shows 0 throughput | VM may be in StorageHashing/Merkle stage - check VM logs |
| ETA shows "no data" | PromQL label mismatch - see [AGENTS.md](AGENTS.md#important-gotchas) gotcha #11 |
| `prevent_destroy` error on provision | Use `_TARGET=module.monitoring` to update only dashboard |
