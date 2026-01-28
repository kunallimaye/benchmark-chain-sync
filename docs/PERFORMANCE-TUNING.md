# op-reth Performance Tuning Guide

This comprehensive guide covers all aspects of performance tuning for op-reth, including reth configuration, Linux system-level optimizations, and bottleneck detection.

## Table of Contents

1. [Overview](#overview)
2. [System Requirements](#system-requirements)
3. [Reth Configuration (reth.toml)](#reth-configuration-rethtoml)
4. [CLI Performance Flags](#cli-performance-flags)
5. [Bottleneck Detection](#bottleneck-detection)
6. [Linux System-Level Tuning](#linux-system-level-tuning)
7. [Current Infrastructure Status](#current-infrastructure-status)
8. [Recommended Configurations](#recommended-configurations)
9. [Performance Impact Analysis](#performance-impact-analysis)
10. [Troubleshooting](#troubleshooting)
11. [Related Documentation](#related-documentation)

---

## Overview

op-reth performance is influenced by three main factors:

1. **Reth Configuration** - Stage thresholds, cache sizes, parallelism settings
2. **System Configuration** - Filesystem, I/O scheduler, kernel parameters
3. **Hardware** - Storage type, CPU cores, memory

### Key Trade-offs

| Goal | Configuration | Trade-off |
|------|---------------|-----------|
| **Fastest sync** | Large batches (500K), max cache | Poor ETA visibility, high memory |
| **Best ETA visibility** | Small batches (20K) | ~7-10% slower sync |
| **Memory-constrained** | Lower cache, smaller batches | Slower sync |

### Reth Sync Pipeline

Reth processes blocks through 12 pipeline stages. Understanding these is crucial for tuning:

| # | Stage | Description | % of Time* |
|---|-------|-------------|------------|
| 1-3 | Headers/Bodies/SenderRecovery | Download and prepare blocks | <2% |
| 4 | **Execution** | Execute transactions (EVM) | **42%** |
| 5 | AccountHashing | Hash account data | 2% |
| 6 | **StorageHashing** | Hash storage data | **25%** |
| 7 | **MerkleExecute** | Compute state root | **17%** |
| 8 | TransactionLookup | Index transactions | 11% |
| 9-12 | History/Prune/Finish | Indexing and cleanup | <3% |

*Based on 525K block sync on c3-standard-176-lssd

**Key Insight:** StorageHashing + MerkleExecute take almost as long as Execution (~12 hours vs ~11.6 hours for 525K blocks).

---

## System Requirements

### Base Mainnet (OP Stack)

| Component | Archive Node | Full Node |
|-----------|-------------|-----------|
| **Disk** | 4.1TB+ (TLC NVMe recommended) | 2TB+ (TLC NVMe recommended) |
| **Memory** | 128GB+ | 128GB+ |
| **CPU** | 6+ cores, high clock speed | 6+ cores, high clock speed |
| **Bandwidth** | Stable 24Mbps+ | Stable 24Mbps+ |

### Storage Considerations

**TLC vs QLC NVMe:**

| Type | Performance | Endurance | Recommendation |
|------|-------------|-----------|----------------|
| TLC (Triple-Level Cell) | Higher | Higher | **Recommended** |
| QLC (Quad-Level Cell) | Lower | Lower | Avoid for databases |

Recommended drives: Seagate Firecuda 530, WD Black SN850X

### CPU Considerations

- **Clock speed > core count** for EVM execution (single-threaded)
- **5+ cores required** for parallel state root task on OP Stack
- Insufficient cores → 2s+ block processing latencies

### GCP Machine Types

| Machine Type | vCPUs | RAM | Storage Options | Use Case |
|--------------|-------|-----|-----------------|----------|
| c3-standard-44 | 44 | 176GB | pd-balanced, pd-ssd | Standard benchmark |
| c3-standard-176 | 176 | 704GB | pd-balanced, pd-ssd | High performance |
| c3-standard-176-lssd | 176 | 704GB | 12TB NVMe RAID-0 | Maximum performance |

---

## Reth Configuration (reth.toml)

Reth reads configuration from `reth.toml` in the data directory. Use `--config` flag to specify a custom path.

### Stage Thresholds (Execution Batch Size)

The execution stage processes blocks in batches. A batch commits when **any** threshold is hit:

```toml
[stages.execution]
# Maximum blocks per batch (default: 500,000)
max_blocks = 500000

# Maximum state changes in memory (default: 5,000,000)
max_changes = 5000000

# Maximum cumulative gas (default: 1.5 trillion = 30M * 50K blocks)
max_cumulative_gas = 1500000000000

# Maximum wall-clock time per batch (default: 10 minutes)
max_duration = "10m"
```

**Why change batch size?**

| Batch Size | Pros | Cons |
|------------|------|------|
| Large (500K) | Fastest sync, fewer commits | Poor ETA visibility, high memory |
| Small (20K) | Better ETA, lower memory, frequent updates | ~7% slower, more commits |

**Recommended for benchmarking (20K blocks):**

```toml
[stages.execution]
max_blocks = 20000
max_changes = 200000
max_cumulative_gas = 600000000000
max_duration = "2m"
```

### Hashing Stage Configuration

```toml
[stages.account_hashing]
# Threshold before full rehash vs incremental (default: 500,000)
clean_threshold = 500000
# Accounts to process before commit (default: 100,000)
commit_threshold = 100000

[stages.storage_hashing]
clean_threshold = 500000
commit_threshold = 100000

[stages.merkle]
# Blocks for incremental root computation (default: 7,000)
incremental_threshold = 7000
# Blocks before full trie rebuild (default: 100,000)
rebuild_threshold = 100000
```

### ETL Configuration

ETL (Extract, Transform, Load) is used for sorted database inserts:

```toml
[stages.etl]
# Optional temp directory (default: datadir/etl-tmp)
# dir = "/mnt/fast-ssd/etl-tmp"

# Max size before flush to disk (default: 500MB)
file_size = 524288000
```

**Tip:** Place ETL temp directory on fast storage for better performance.

### Headers and Bodies (Network Stages)

```toml
[stages.headers]
downloader_max_concurrent_requests = 100
downloader_min_concurrent_requests = 5
downloader_max_buffered_responses = 100
downloader_request_limit = 1000
commit_threshold = 10000

[stages.bodies]
downloader_request_limit = 200
downloader_stream_batch_size = 1000
downloader_max_buffered_blocks_size_bytes = 2147483648  # 2GB
downloader_min_concurrent_requests = 5
downloader_max_concurrent_requests = 100
```

### Sender Recovery

```toml
[stages.sender_recovery]
# Transactions to recover before commit (default: 5,000,000)
commit_threshold = 5000000
```

### Transaction Lookup

```toml
[stages.transaction_lookup]
# Transactions before commit (default: 5,000,000)
chunk_size = 5000000
```

### History Indexing

```toml
[stages.index_account_history]
commit_threshold = 100000

[stages.index_storage_history]
commit_threshold = 100000
```

### Complete Example: Benchmarking Configuration

```toml
# =============================================================================
# reth.toml - Optimized for Benchmarking (20K batch size)
# =============================================================================
# Trade-off: ~7% slower sync for better ETA visibility and lower memory usage

[stages.execution]
max_blocks = 20000
max_changes = 200000
max_cumulative_gas = 600000000000
max_duration = "2m"

[stages.account_hashing]
clean_threshold = 500000
commit_threshold = 100000

[stages.storage_hashing]
clean_threshold = 500000
commit_threshold = 100000

[stages.merkle]
incremental_threshold = 7000
rebuild_threshold = 100000

[stages.sender_recovery]
commit_threshold = 5000000

[stages.transaction_lookup]
chunk_size = 5000000

[stages.etl]
file_size = 524288000
```

---

## CLI Performance Flags

### Engine Options

| Flag | Description | Default | Recommendation |
|------|-------------|---------|----------------|
| `--engine.cross-block-cache-size` | Cross-block cache in MB | 4096 (4GB) | Set to 10-20% of RAM |
| `--engine.storage-worker-count` | State root storage workers | auto | Set to vCPU count |
| `--engine.account-worker-count` | State root account workers | auto | Set to vCPU count |
| `--engine.reserved-cpu-cores` | CPU cores reserved for non-reth | 1 | 0 for dedicated nodes |
| `--engine.disable-prewarming` | Disable parallel prewarming | false | Keep enabled (false) |
| `--engine.disable-state-cache` | Disable state cache | false | Keep enabled (false) |

**Current infrastructure settings:**

```bash
--engine.cross-block-cache-size 16384   # 16GB for 44 vCPU machines
--engine.cross-block-cache-size 65536   # 64GB for 176 vCPU machines
--engine.storage-worker-count 44        # Matches vCPU count
--engine.account-worker-count 44        # Matches vCPU count
--engine.reserved-cpu-cores 0           # Use all cores
```

### Database Options (MDBX)

| Flag | Description | Default | Recommendation |
|------|-------------|---------|----------------|
| `--db.max-size` | Maximum database size | 8TB | Set to disk size |
| `--db.growth-step` | Database growth increment | auto | 4GB for large DBs |
| `--db.page-size` | Database page size | 4KB | **Immutable after creation** |
| `--db.read-transaction-timeout` | Read transaction timeout | 0 (none) | 0 for sync |
| `--db.exclusive` | Open in exclusive mode | false | true for NFS |

**Page Size Note:** The default 4KB page size limits max DB to 8TB (MDBX supports 2^31 pages). For larger databases, use 8KB or 16KB pages, but this can only be set at database creation time.

**Not currently configured in infrastructure.** Consider adding:

```bash
--db.max-size 15000000000000   # 15TB for 15TB disks
--db.growth-step 4294967296    # 4GB growth steps
```

### RPC Cache Options

Less important for sync benchmarks, but relevant for RPC-heavy workloads:

| Flag | Description | Default |
|------|-------------|---------|
| `--rpc-cache.max-blocks` | Max blocks in cache | 5000 |
| `--rpc-cache.max-receipts` | Max receipts in cache | 2000 |
| `--rpc-cache.max-concurrent-db-requests` | Concurrent DB requests | 512 |

---

## Bottleneck Detection

### Key Metrics at a Glance

| Metric | Purpose | Healthy Range |
|--------|---------|---------------|
| `reth_sync_execution_gas_per_second` | Primary throughput | Higher is better |
| `reth_sync_execution_execution_duration` | EVM execution time | Lower is better |
| `reth_sync_block_validation_state_root_duration` | State root time | Lower is better |
| `reth_database_transaction_close_duration_seconds` | DB commit latency | <100ms avg |
| `reth_sync_caching_*_cache_hits/misses` | Cache efficiency | >80% hit rate |
| `reth_jemalloc_resident` | Memory usage | Within limits |

### Bottleneck Types

| Type | Indicator | Cause | Resolution |
|------|-----------|-------|------------|
| **CPU-bound** | `execution_duration` >> `state_root_duration` | EVM computation | More/faster CPU |
| **I/O-bound (State Root)** | `state_root_duration` >> `execution_duration` | Disk reads for proofs | Faster storage |
| **I/O-bound (DB Write)** | High `transaction_close_duration` | Disk write latency | Faster storage |
| **Memory Pressure** | `jemalloc_resident` near limit | Insufficient RAM | More memory, lower cache |
| **Cache Thrashing** | Cache hit rate <50% | Working set > cache | Increase cache size |

### Bottleneck Decision Tree

```
                        Low gas/s throughput?
                               |
           +-------------------+-------------------+
           v                                       v
    Check: execution_duration              Check: DB commit latency
    vs state_root_duration                 (transaction_close_duration)
           |                                       |
     +-----+-----+                          +------+------+
     v           v                          v             v
 exec >> sr   sr >> exec              High (>100ms)    Normal
     |           |                          |             |
     v           v                          v             v
   CPU         I/O                      DB WRITE      Check:
 BOUND    (State Root)                 BOTTLENECK    - Memory
     |        BOUND                         |        - Cache
     v           v                          v          hit %
 Check:      Check:                     Check:
 - CPU %     - Disk I/O                 - Disk
 - Cache     - Proof workers            - Write
   hits      - Parallelism                latency
```

### PromQL Queries for Diagnosis

**Bottleneck Ratio (Primary Indicator):**

```promql
# Ratio > 1: I/O bound (state root)
# Ratio < 1: CPU bound (execution)
reth_sync_block_validation_state_root_duration / reth_sync_execution_execution_duration
```

**CPU Bottleneck Queries:**

```promql
# CPU cores used
rate(reth_process_cpu_seconds_total[1m])

# Execution gas throughput
reth_sync_execution_gas_per_second

# Precompile cache efficiency
rate(reth_sync_caching_precompile_cache_hits[5m]) / 
(rate(reth_sync_caching_precompile_cache_hits[5m]) + 
 rate(reth_sync_caching_precompile_cache_misses[5m]))
```

**I/O Bottleneck Queries:**

```promql
# State root computation time
reth_sync_block_validation_state_root_duration

# DB commit latency (average)
rate(reth_database_transaction_close_duration_seconds_sum{outcome="commit"}[5m]) /
rate(reth_database_transaction_close_duration_seconds_count{outcome="commit"}[5m])

# DB commit latency (p99)
histogram_quantile(0.99, 
  rate(reth_database_transaction_close_duration_seconds_bucket{outcome="commit"}[5m]))
```

**Memory Queries:**

```promql
# Memory usage (GB)
reth_jemalloc_resident / 1024 / 1024 / 1024

# Process memory
reth_process_resident_memory_bytes / 1024 / 1024 / 1024
```

**Cache Efficiency Queries:**

```promql
# Account cache hit rate
rate(reth_sync_caching_account_cache_hits[5m]) / 
(rate(reth_sync_caching_account_cache_hits[5m]) + 
 rate(reth_sync_caching_account_cache_misses[5m]))

# Storage cache hit rate
rate(reth_sync_caching_storage_cache_hits[5m]) / 
(rate(reth_sync_caching_storage_cache_hits[5m]) + 
 rate(reth_sync_caching_storage_cache_misses[5m]))
```

**Sync Progress Queries:**

```promql
# Execution stage checkpoint
reth_sync_checkpoint{stage="Execution"}

# Execution throughput (blocks/s)
rate(reth_sync_checkpoint{stage="Execution"}[5m])

# Gas throughput (smoothed)
avg_over_time(reth_sync_execution_gas_per_second[5m])
```

### Using Cloud Trace

Tracing is enabled with 1% sampling by default. Use for deep-dive analysis when metrics indicate an issue.

**When to Use Traces:**

| Scenario | Use Traces? |
|----------|-------------|
| Identifying bottleneck category | No, use metrics |
| Understanding why a specific block was slow | Yes |
| Investigating latency outliers | Yes |
| Correlating delays across components | Yes |

**Accessing Traces:**

1. Cloud Console → Trace → Trace Explorer
2. Filter by service name: `op-reth-<vm_name>`
3. Sort by latency to find slow operations

**Increasing Trace Sampling (for debugging):**

```toml
# config.toml
[tracing]
enabled = true
sample_ratio = 0.10  # 10% sampling
filter = "debug"     # More detailed spans
```

---

## Linux System-Level Tuning

### Filesystem Mount Options

**Recommended: XFS with optimized mount options**

```bash
# /etc/fstab entry
/dev/nvme0n1 /mnt/data xfs defaults,noatime,nodiratime,discard 0 0

# For ext4 (if required)
/dev/sda1 /mnt/data ext4 defaults,noatime,nodiratime,discard,data=ordered 0 0
```

| Mount Option | Purpose | Impact |
|--------------|---------|--------|
| `noatime` | Disable access time updates | **Critical** - reduces write amplification for mmap workloads |
| `nodiratime` | Disable directory access time | Reduces metadata writes |
| `discard` | Enable TRIM/discard | Good for SSD longevity |

**Why `noatime` is critical:** MDBX uses mmap, so every page access would trigger an atime update without this option, causing massive write amplification.

### I/O Scheduler Configuration

| Storage Type | Recommended Scheduler | Rationale |
|--------------|----------------------|-----------|
| NVMe / Local SSD (LSSD) | `none` | Device handles parallelism internally |
| Persistent Disk (pd-ssd, pd-balanced) | `mq-deadline` | Provides fairness for network storage |

**Check current scheduler:**

```bash
cat /sys/block/nvme0n1/queue/scheduler
```

**Set scheduler:**

```bash
# For NVMe
echo none > /sys/block/nvme0n1/queue/scheduler

# For Persistent Disk
echo mq-deadline > /sys/block/sda/queue/scheduler
```

**Persistent via udev rule (`/etc/udev/rules.d/60-io-scheduler.rules`):**

```bash
# NVMe devices
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"

# Persistent disk (virtio)
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/scheduler}="mq-deadline"
```

### sysctl Parameters (Virtual Memory)

```bash
# /etc/sysctl.d/99-mdbx-tuning.conf

# =============================================================================
# Dirty Page Management - CRITICAL for MDBX
# =============================================================================

# Percentage of system memory that can be dirty before processes block
# Lower = more frequent, smaller writes; reduces latency spikes
vm.dirty_ratio = 10

# Percentage when background writeback starts
vm.dirty_background_ratio = 5

# How long data can be dirty before write (centiseconds)
vm.dirty_expire_centisecs = 1500

# How often flusher thread wakes up (centiseconds)
vm.dirty_writeback_centisecs = 100

# =============================================================================
# Swappiness - CRITICAL for memory-mapped databases
# =============================================================================

# 0-100: How aggressively to swap vs drop cache
# Low value = keep database pages in RAM
vm.swappiness = 10

# =============================================================================
# VFS Cache Pressure
# =============================================================================

# Controls tendency to reclaim dentry/inode cache vs page cache
# Lower = prefer keeping dentry/inode cache
vm.vfs_cache_pressure = 50

# =============================================================================
# Memory Map Limits - Essential for large MDBX databases
# =============================================================================

# Maximum memory map areas per process
# MDBX may need many mappings for large databases
vm.max_map_count = 1000000

# =============================================================================
# Zone Reclaim (NUMA systems)
# =============================================================================

# 0 = disabled (allocate from any node)
# For database workloads: 0 is usually better
vm.zone_reclaim_mode = 0
```

**Apply immediately:**

```bash
sysctl -p /etc/sysctl.d/99-mdbx-tuning.conf
```

### Block Device Tuning

```bash
# Queue depth - higher for parallel I/O
echo 256 > /sys/block/nvme0n1/queue/nr_requests

# Read-ahead - lower for random I/O (MDBX B+tree access)
echo 128 > /sys/block/nvme0n1/queue/read_ahead_kb
```

| Parameter | NVMe/LSSD | Persistent Disk | Why |
|-----------|-----------|-----------------|-----|
| `nr_requests` | 256 | 256 | Higher queue depth for parallel I/O |
| `read_ahead_kb` | 64-128 | 256 | Lower for random I/O (MDBX) |

### Transparent Huge Pages (THP)

**Recommendation: `madvise` or `never`**

```bash
# Check current status
cat /sys/kernel/mm/transparent_hugepage/enabled

# Set to madvise (application opt-in)
echo madvise > /sys/kernel/mm/transparent_hugepage/enabled
echo madvise > /sys/kernel/mm/transparent_hugepage/defrag
```

| THP Setting | Recommendation | Rationale |
|-------------|----------------|-----------|
| `enabled` | `madvise` | App can opt-in; avoids memory bloat |
| `defrag` | `madvise` | Reduces compaction stalls |

**Alternative:** Some database workloads perform better with THP completely disabled:

```bash
echo never > /sys/kernel/mm/transparent_hugepage/enabled
```

### NUMA Considerations

For large memory systems (176+ vCPUs):

```bash
# Check NUMA topology
numactl --hardware

# Verify NUMA balancing is enabled (recommended)
cat /proc/sys/kernel/numa_balancing
# Should be: 1
```

**Recommendation:** Let the kernel handle NUMA automatically. Forcing specific binding can cause contention.

### Complete Tuning Script

```bash
#!/bin/bash
# /opt/op-reth/tune-system.sh
# Run at boot via systemd or startup script

set -e

# Detect primary data disk
DATA_DISK="${1:-nvme0n1}"
DEVICE="/dev/${DATA_DISK}"

if [ ! -b "$DEVICE" ]; then
    echo "Device $DEVICE not found, trying sda..."
    DATA_DISK="sda"
fi

echo "Tuning system for MDBX/blockchain workloads..."

# =============================================================================
# I/O Scheduler
# =============================================================================
SCHEDULER_PATH="/sys/block/${DATA_DISK}/queue/scheduler"
if [ -f "$SCHEDULER_PATH" ]; then
    if [[ "$DATA_DISK" == nvme* ]]; then
        echo none > "$SCHEDULER_PATH"
        echo "Set scheduler to 'none' for NVMe"
    else
        echo mq-deadline > "$SCHEDULER_PATH"
        echo "Set scheduler to 'mq-deadline' for block device"
    fi
fi

# =============================================================================
# Block Device Tuning
# =============================================================================
QUEUE_PATH="/sys/block/${DATA_DISK}/queue"
if [ -d "$QUEUE_PATH" ]; then
    echo 256 > "${QUEUE_PATH}/nr_requests" 2>/dev/null || true
    echo 128 > "${QUEUE_PATH}/read_ahead_kb" 2>/dev/null || true
    echo "Set queue parameters"
fi

# =============================================================================
# VM/Memory Settings
# =============================================================================
sysctl -w vm.dirty_ratio=10
sysctl -w vm.dirty_background_ratio=5
sysctl -w vm.dirty_expire_centisecs=1500
sysctl -w vm.dirty_writeback_centisecs=100
sysctl -w vm.swappiness=10
sysctl -w vm.vfs_cache_pressure=50
sysctl -w vm.max_map_count=1000000
sysctl -w vm.zone_reclaim_mode=0
echo "Applied VM tuning parameters"

# =============================================================================
# Transparent Huge Pages
# =============================================================================
THP_PATH="/sys/kernel/mm/transparent_hugepage"
if [ -d "$THP_PATH" ]; then
    echo madvise > "${THP_PATH}/enabled"
    echo madvise > "${THP_PATH}/defrag"
    echo "Set THP to 'madvise'"
fi

echo "System tuning complete!"
```

---

## Current Infrastructure Status

### What's Configured

| Setting | Status | Location |
|---------|--------|----------|
| `--engine.cross-block-cache-size` | ✅ 16GB/64GB | `op-reth.service.j2` |
| `--engine.storage-worker-count` | ✅ Matches vCPU | `op-reth.service.j2` |
| `--engine.account-worker-count` | ✅ Matches vCPU | `op-reth.service.j2` |
| `--engine.reserved-cpu-cores` | ✅ 0 | `op-reth.service.j2` |
| Tracing (OTLP to Cloud Trace) | ✅ 1% sampling | `op-reth.service.j2` |
| ulimits (LimitNOFILE) | ✅ 65535 | `op-reth.service.j2` |

### What's NOT Configured

| Setting | Status | Impact | Priority |
|---------|--------|--------|----------|
| `reth.toml` config file | ❌ Not deployed | No batch size control | High |
| `--db.max-size` | ❌ Default 8TB | May limit large DBs | Medium |
| `--db.growth-step` | ❌ Default | Suboptimal for NVMe | Low |
| Filesystem mount options | ❌ Not set | Missing `noatime` | High |
| I/O scheduler | ❌ Default | May not be optimal | Medium |
| sysctl tuning | ❌ Not set | Suboptimal VM settings | Medium |
| THP configuration | ❌ Default | May cause memory bloat | Low |

### Implementation Priority

1. **High:** Mount options (`noatime`), `reth.toml` for batch size
2. **Medium:** sysctl tuning, I/O scheduler, `--db.max-size`
3. **Low:** THP, block device tuning, `--db.growth-step`

---

## Recommended Configurations

### Profile 1: Fastest Sync (Production)

Optimize for minimum total sync time.

**reth.toml:**

```toml
# Use defaults (500K blocks per batch)
[stages.execution]
max_blocks = 500000
max_changes = 5000000
max_cumulative_gas = 1500000000000
max_duration = "10m"
```

**CLI flags:**

```bash
--engine.cross-block-cache-size 65536    # 64GB for 176 vCPU
--engine.storage-worker-count 176
--engine.reserved-cpu-cores 0
```

**Trade-offs:**
- ✅ Fastest total time
- ❌ Poor ETA visibility (hours between stage updates)
- ❌ Higher memory usage

### Profile 2: Best ETA Visibility (Benchmarking)

Optimize for monitoring and ETA calculation.

**reth.toml:**

```toml
[stages.execution]
max_blocks = 20000
max_changes = 200000
max_cumulative_gas = 600000000000
max_duration = "2m"
```

**CLI flags:** Same as Profile 1

**Trade-offs:**
- ✅ Frequent checkpoint updates
- ✅ Accurate ETA calculation
- ❌ ~7% slower total sync

### Profile 3: Memory-Constrained

For systems with limited RAM.

**reth.toml:**

```toml
[stages.execution]
max_blocks = 50000
max_changes = 500000
max_cumulative_gas = 150000000000
max_duration = "5m"
```

**CLI flags:**

```bash
--engine.cross-block-cache-size 4096     # 4GB (default)
--engine.storage-worker-count 16         # Limit parallelism
--engine.reserved-cpu-cores 2            # Reserve for OS
```

**Trade-offs:**
- ✅ Lower memory footprint
- ❌ Slower sync

---

## Performance Impact Analysis

### Batch Size Impact on Sync Time

Based on observed metrics from `op-reth-c3-standard-176-lssd`:

```
MDBX commit time: 3,444 seconds for 740 commits
Average commit time: 4.65 seconds per commit
```

| Batch Size | Commits for 500K blocks | Commit Overhead |
|------------|------------------------|-----------------|
| 500,000 | 1 | ~5 seconds |
| 50,000 | 10 | ~50 seconds |
| 20,000 | 25 | ~120 seconds |
| 10,000 | 50 | ~240 seconds |

### Estimated Total Sync Time Impact

For a 500K block sync (~27 hour baseline on c3-standard-176-lssd):

| Batch Size | Estimated Overhead | Total Time | Impact |
|------------|-------------------|------------|--------|
| 500,000 | ~0.5% | 27.0 hours | Baseline |
| 50,000 | ~3% | 27.8 hours | +3% |
| 20,000 | ~7% | 28.9 hours | +7% |
| 10,000 | ~15% | 31.0 hours | +15% |

### Storage Type Performance Comparison

| Storage Type | Execution (MGas/s) | Notes |
|--------------|-------------------|-------|
| NVMe RAID-0 (LSSD, no TDX) | 1,139 | Best performance |
| NVMe RAID-0 (LSSD, TDX) | 700 | ~40% TDX overhead |
| pd-balanced (no TDX) | 496-552 | Baseline |
| pd-balanced (TDX) | 527-533 | Minimal TDX impact |
| pd-ssd (no TDX) | 527-552 | Similar to pd-balanced |

---

## Troubleshooting

### No Metrics in Dashboard

1. **Check Ops Agent is running:**
   ```bash
   systemctl status google-cloud-ops-agent
   ```

2. **Verify op-reth metrics endpoint:**
   ```bash
   curl localhost:9001/metrics | head -50
   ```

3. **Check Ops Agent config:**
   ```bash
   cat /etc/google-cloud-ops-agent/config.yaml
   ```

4. **Check Ops Agent logs:**
   ```bash
   journalctl -u google-cloud-ops-agent -f
   ```

### No Traces in Cloud Trace

1. **Verify tracing is enabled in op-reth:**
   ```bash
   ps aux | grep op-reth | grep tracing-otlp
   ```

2. **Check Ops Agent OTLP receiver:**
   ```bash
   ss -tlnp | grep 4317
   ```

3. **Verify service account has `roles/cloudtrace.agent`:**
   ```bash
   gcloud projects get-iam-policy PROJECT_ID \
     --flatten="bindings[].members" \
     --filter="bindings.role:cloudtrace.agent"
   ```

### High Trace Volume / Cost

Reduce sampling ratio in `config.toml`:

```toml
[tracing]
enabled = true
sample_ratio = 0.001  # 0.1% sampling
filter = "info"
```

Then run `make configure` to apply.

### Dashboard Shows 0 Throughput

When a VM is not in the Execution stage, throughput shows 0. Check current stage:

```bash
sudo journalctl -u op-reth --since '1 minute ago' --no-pager | grep -i stage
```

| Dashboard Shows | Likely Stage | Action |
|-----------------|--------------|--------|
| Execution: 0, Hashing: active | StorageHashing/MerkleExecute | Normal - wait |
| All rows: 0 | Between batches | Check logs |

### Sync Slower Than Expected

1. Check bottleneck type using PromQL queries above
2. Review cache hit rates
3. Check disk I/O latency
4. Verify system tuning is applied

---

## Related Documentation

- [ETA-CALC.md](ETA-CALC.md) - Sync ETA calculation methods and PromQL queries
- [AGENTS.md](../AGENTS.md) - Infrastructure reference and dashboard configuration
- [Reth Configuration Reference](https://paradigmxyz.github.io/reth/run/configuration) - Official reth docs
- [Reth System Requirements](https://paradigmxyz.github.io/reth/run/system-requirements) - Official requirements

---

## References

- libmdbx Documentation: https://libmdbx.dqdkfa.ru/intro.html
- Linux Kernel VM Documentation: https://www.kernel.org/doc/html/latest/admin-guide/sysctl/vm.html
- GCP Optimize Persistent Disk: https://cloud.google.com/compute/docs/disks/optimizing-pd-performance
- GCP Optimize Local SSD: https://cloud.google.com/compute/docs/disks/optimizing-local-ssd-performance
- Reth Stages Source: https://github.com/paradigmxyz/reth/tree/main/crates/stages
