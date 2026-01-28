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

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        SHARED DOWNLOAD DISK                                  │
│   ┌─────────────────────────────────────────────┐                           │
│   │  op-reth-snapshot-download (8TB pd-balanced)│                           │
│   │  /snapshot.tar.zst                          │                           │
│   │  Downloaded once, shared read-only          │                           │
│   └───────────────────┬─────────────────────────┘                           │
│                       │                                                      │
│         ┌─────────────┼─────────────┬─────────────┐                         │
│         ▼             ▼             ▼             ▼                         │
│   ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐                   │
│   │ VM 1      │ │ VM 2      │ │ VM 3      │ │ VM 4      │                   │
│   │ pd-balanced│ │ pd-ssd    │ │ hyperdisk │ │ lssd      │                   │
│   │ TDX       │ │ TDX       │ │ TDX       │ │ 176 vCPU  │                   │
│   └─────┬─────┘ └─────┬─────┘ └─────┬─────┘ └─────┬─────┘                   │
│         │             │             │             │                         │
│         └─────────────┴──────┬──────┴─────────────┘                         │
│                              ▼                                              │
│                    ┌─────────────────┐                                      │
│                    │  BNE (L1 Node)  │                                      │
│                    │  - JSON-RPC     │                                      │
│                    │  - Beacon API   │                                      │
│                    └─────────────────┘                                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- GCP project with required APIs enabled
- `gcloud` CLI configured with project access
- Access to the snapshot GCS bucket

**For detailed setup instructions (Cloud Build permissions, Manual IAM setup), see [AGENTS.md](AGENTS.md#prerequisites-for-development).**

## Quick Start

### 1. Create L1 BNE Node (One-time)

```bash
# Create Blockchain Node Engine node (takes days to sync!)
make create-l1

# Check sync status
make status-l1
```

### 2. Configure Secrets

Create API key in GCP Console (APIs & Services > Credentials) after BNE syncs:

```bash
# Create .env file with API key
echo "L1_API_KEY=your-api-key" > .env
```

### 3. Build Binaries

```bash
make build-reth      # Build op-reth from source
make build-op-node   # Build op-node (extract from Docker)
```

### 4. Create Shared Download Disk (One-time)

```bash
# Create the shared 8TB download disk
make create-download-disk

# Download snapshot to shared disk (2-3 hours)
make download

# Monitor download progress
make download-status
```

### 5. Configure VMs in config.toml

Edit `config.toml` to define VM instances:

```toml
[download]
snapshot_url = "gs://base-mainnet-snapshot/base-mainnet-reth-1768474496.tar.zst"
disk_name = "op-reth-snapshot-download"
disk_size_gb = 8000
disk_type = "pd-balanced"

[[vm]]
name = "op-reth-c3-standard-44-pd-balanced"
reth_version = "6df249c"
# No snapshot_url here - uses shared download disk
```

### 6. Provision and Configure

```bash
# Create VM infrastructure (attaches download disk read-only)
make provision VM=op-reth-c3-standard-44-pd-balanced

# Configure VM (extracts snapshot from shared disk, starts services)
make configure VM=op-reth-c3-standard-44-pd-balanced

# Monitor extraction progress
make configure-status VM=op-reth-c3-standard-44-pd-balanced
```

### 7. Run Benchmark

```bash
# After extraction completes and services start
make benchmark VM=op-reth-c3-standard-44-pd-balanced
```

### 8. Cleanup

```bash
make cleanup VM=op-reth-c3-standard-44-pd-balanced

# To delete the shared download disk (optional)
make delete-download-disk
```

## Configuration

### config.toml

```toml
[project]
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"
network = "base-mainnet"
gcs_bucket = "base-mainnet-snapshot"

[l1]
rpc_endpoint = "https://json-rpc.xxx.blockchainnodeengine.com"
beacon_endpoint = "https://beacon.xxx.blockchainnodeengine.com"

[build]
reth_repo = "https://github.com/paradigmxyz/reth.git"
reth_branch = "main"
op_node_version = "v1.16.5"

[download]
snapshot_url = "gs://bucket/snapshot.tar.zst"
disk_name = "op-reth-snapshot-download"
disk_size_gb = 8000
disk_type = "pd-balanced"
downloader_machine_type = "n2-standard-8"

[defaults.vm]
disk_size_gb = 15000
machine_type = "c3-standard-44"
storage_type = "pd-balanced"
confidential_compute = true

[[vm]]
name = "op-reth-c3-standard-44-pd-balanced"
reth_version = "6df249c"

[[vm]]
name = "op-reth-c3-standard-44-hyperdisk-tdx"
storage_type = "hyperdisk-extreme"
provisioned_iops = 350000
provisioned_throughput = 5000
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

# Shared Download Disk
make create-download-disk        # Create shared download disk (one-time)
make download                    # Download snapshot to disk (~2-3 hours)
make download-status             # Check download progress
make delete-download-disk        # Delete download disk (with confirmation)

# Provision & Configure
make provision                   # Create all VMs
make provision VM=<name>         # Create specific VM
make configure                   # Configure all VMs (parallel extraction!)
make configure VM=<name>         # Configure specific VM

# Status & Monitoring
make status                      # Show builds, VMs, L1, download disk status
make list-vms                    # List VMs in config.toml
make list-instances              # List active Terraform instances
make configure-status VM=<name>  # SSH to VM, show extraction progress
make extract-status VM=<name>    # Alias for configure-status

# Benchmark
make benchmark VM=<name>         # Run benchmark on VM

# Cleanup
make cleanup                     # Destroy all VMs (keeps download disk)
make cleanup VM=<name>           # Destroy specific VM
```

## Shared Download Disk Workflow

The snapshot is downloaded once to a shared disk, then extracted to each VM in parallel:

1. **Create download disk** (`make create-download-disk`) - 8TB pd-balanced disk
2. **Download snapshot** (`make download`) - Creates temp VM, downloads with aria2c, destroys VM
3. **Provision VMs** (`make provision`) - Creates VMs with download disk attached read-only
4. **Configure VMs** (`make configure`) - Extracts snapshot from shared disk to each VM's data disk

### Benefits
- Download once, extract many times
- Parallel extraction on all VMs
- No per-VM download = faster provisioning
- Easy to add new VMs anytime

### Monitor Progress

```bash
# Check download progress (while downloading)
make download-status

# Check extraction progress on a VM
make configure-status VM=op-reth-c3-standard-44-pd-balanced

# Or manually SSH
gcloud compute ssh <vm-name> --zone=us-central1-a \
  --command='cat /mnt/data/.extract-status'
```

### Status Files

**Download status** (on download disk): `/mnt/download/.download-status`
```json
{"stage": "downloading", "progress": "47%", "timestamp": "..."}
{"stage": "complete", "progress": "100%", "timestamp": "..."}
```

**Extract status** (on each VM): `/mnt/data/.extract-status`
```json
{"stage": "extracting", "progress": "23%", "timestamp": "..."}
{"stage": "ready", "progress": "100%", "timestamp": "..."}
```

## VM Types

The infrastructure supports various storage types for benchmarking:

| Storage Type | TDX | Description |
|--------------|-----|-------------|
| `pd-balanced` | Yes/No | General-purpose SSD (default) |
| `pd-ssd` | Yes/No | Higher IOPS SSD |
| `hyperdisk-extreme` | Yes/No | Highest performance (350K IOPS, 5GB/s) |
| `lssd` | Yes/No | Local NVMe RAID-0 (176 vCPUs, 704GB RAM) |

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
