# ETA Calculation for op-reth Sync Stages

This document explains how to calculate Estimated Time of Arrival (ETA) for op-reth sync completion based on available metrics.

## Table of Contents

1. [Overview](#overview)
2. [Reth Sync Pipeline](#reth-sync-pipeline)
3. [Available Metrics](#available-metrics)
4. [ETA Calculation Methods](#eta-calculation-methods)
5. [PromQL Queries](#promql-queries)
6. [Historical Benchmarks](#historical-benchmarks)
7. [Dashboard Implementation](#dashboard-implementation)

---

## Overview

Reth processes blocks through a pipeline of stages. Each stage must complete before the next can begin (for a given batch of blocks). To calculate overall sync ETA, we need to:

1. Identify which stage each VM is currently in
2. Calculate time remaining for the current stage
3. Estimate time for remaining stages based on historical data

### Challenge

When a stage hasn't started yet, `rate()` returns 0, making direct ETA calculation impossible. We must use:
- Historical data from completed stages
- Cross-VM data from VMs that have completed those stages
- Estimated ratios based on entity counts

---

## Reth Sync Pipeline

### Stage Execution Order

| # | Stage | Description | Entities | Typical Time* |
|---|-------|-------------|----------|---------------|
| 1 | Headers | Download block headers | blocks | <1% |
| 2 | Bodies | Download block bodies | blocks | <1% |
| 3 | SenderRecovery | Recover tx senders from signatures | transactions | <1% |
| 4 | **Execution** | Execute transactions (EVM) | gas | **42%** |
| 5 | AccountHashing | Hash account data | accounts | 2% |
| 6 | **StorageHashing** | Hash storage data | storage slots | **25%** |
| 7 | **MerkleExecute** | Compute state root | trie nodes | **17%** |
| 8 | TransactionLookup | Index transactions by hash | transactions | 11% |
| 9 | IndexStorageHistory | Index storage history | entries | <1% |
| 10 | IndexAccountHistory | Index account history | entries | <1% |
| 11 | Prune | Prune unnecessary data | entries | <1% |
| 12 | Finish | Final cleanup and commit | blocks | <1% |

*Percentages based on observed sync of 525K blocks (block 40.8M to 41.4M)

### Key Insight

**StorageHashing + MerkleExecute together take almost as long as Execution!**

For a 525K block batch:
- Execution: ~11.6 hours
- StorageHashing: ~6.9 hours
- MerkleExecute: ~4.8 hours
- TransactionLookup: ~2.9 hours

---

## Available Metrics

### Core Stage Metrics

| Metric | Labels | Description |
|--------|--------|-------------|
| `reth_sync_checkpoint` | `stage` | Current block number for each stage |
| `reth_sync_entities_processed` | `stage` | Entities processed (gas/blocks/accounts/etc.) |
| `reth_sync_entities_total` | `stage` | Total entities to process (0 for some stages) |
| `reth_sync_total_elapsed` | `stage` | Cumulative time spent in stage (seconds) |

### Execution-Specific Metrics

| Metric | Description |
|--------|-------------|
| `reth_sync_execution_gas_per_second` | Current gas throughput |
| `reth_sync_execution_execution_duration` | Time spent executing blocks |

### L2 Chain Tip

| Metric | Labels | Description |
|--------|--------|-------------|
| `op_node_default_refs_number` | `layer="l2"`, `type="l2_unsafe"` | Current L2 chain tip |

---

## Dashboard Metric Selection by Stage

For building dashboards, each stage requires different metric sources based on update frequency. Prometheus metrics (`reth_sync_checkpoint`) only update when a stage commits, which can take hours for long-running stages. Log-based metrics provide real-time visibility.

### Log-Based Metric: `reth_stage_log_count`

We have a custom log-based metric that extracts fields from op-reth status logs:

```
INFO Status connected_peers=29 stage=MerkleExecute checkpoint=40840749 target=41365935 stage_progress=16.93% stage_eta=12h32m27s
```

| Label | Description | Availability |
|-------|-------------|--------------|
| `vm_name` | VM hostname | All stages |
| `stage` | Current pipeline stage | All stages |
| `checkpoint` | Current block number | All stages |
| `target` | Target block number | All stages |
| `stage_progress` | Progress percentage (e.g., "16.93") | Execution, MerkleExecute only |
| `stage_eta` | Time remaining (e.g., "12h32m27s") | **MerkleExecute only** |

### Log Field Availability by Stage

Based on actual log analysis:

| Stage | `checkpoint` | `target` | `stage_progress` | `stage_eta` |
|-------|--------------|----------|------------------|-------------|
| Headers | Yes | Yes | No | No |
| Bodies | Yes | Yes | No | No |
| SenderRecovery | Yes | Yes | No | No |
| **Execution** | Yes | Yes | **Yes** | No |
| AccountHashing | Yes | Yes | No | No |
| **StorageHashing** | Yes | Yes | No | No |
| **MerkleExecute** | Yes | Yes | **Yes** | **Yes** |
| TransactionLookup | Yes | Yes | No | No |
| IndexStorageHistory | Yes | Yes | No | No |
| IndexAccountHistory | Yes | Yes | No | No |
| Prune | Yes | Yes | No | No |
| Finish | Yes | Yes | No | No |

**Key Insight:** Only **MerkleExecute** provides both `stage_progress` and `stage_eta` in logs.

### Prometheus Entity Availability by Stage

Not all stages have meaningful `reth_sync_entities_total` values:

| Stage | `entities_total` > 0? | Entity Type |
|-------|----------------------|-------------|
| Headers | Yes | blocks |
| Bodies | Yes | blocks |
| SenderRecovery | Yes | transactions |
| Execution | Yes | gas |
| AccountHashing | Yes | accounts |
| **StorageHashing** | **No** | - |
| **MerkleExecute** | **No** | - |
| **TransactionLookup** | **No** | - |
| IndexStorageHistory | **No** | - |
| IndexAccountHistory | **No** | - |
| Prune | **No** | - |
| Finish | **No** | - |

### Recommended Metric Source per Stage

| Stage | Throughput | Checkpoint | ETA Calculation |
|-------|------------|------------|-----------------|
| **01-Headers** | Prometheus `rate(reth_sync_checkpoint{stage="Headers"}[5m])` | Prometheus `reth_sync_checkpoint` | Block-based: `(L2_tip - ckpt) / rate / 3600` |
| **02-Bodies** | Prometheus `rate(reth_sync_checkpoint{stage="Bodies"}[5m])` | Prometheus `reth_sync_checkpoint` | Block-based |
| **03-SenderRecovery** | Prometheus `rate(reth_sync_checkpoint{stage="SenderRecovery"}[5m])` | Prometheus `reth_sync_checkpoint` | Block-based |
| **04-Execution** | Prometheus `rate(reth_sync_checkpoint{stage="Execution"}[5m])` | Prometheus `reth_sync_checkpoint` | Block-based: `(L2_tip - ckpt) / rate / 3600` |
| **05-AccountHashing** | Prometheus `rate(reth_sync_entities_processed{stage="AccountHashing"}[5m])` | Prometheus `reth_sync_checkpoint` | Entity-based: `(total - processed) / rate / 3600` |
| **06-StorageHashing** | Prometheus (0 until done) | **Log-based** `checkpoint` label | Historical rate: `(Execution_ckpt - ckpt) / 21 / 3600` |
| **07-MerkleExecute** | Prometheus (0 until done) | **Log-based** `checkpoint` label | **Log-based** `stage_eta` label |
| **08-TransactionLookup** | Prometheus `rate(reth_sync_checkpoint{stage="TransactionLookup"}[5m])` | Prometheus `reth_sync_checkpoint` | Block-based |
| **09-IndexStorageHistory** | Prometheus `rate(reth_sync_checkpoint{stage="IndexStorageHistory"}[5m])` | Prometheus `reth_sync_checkpoint` | Block-based |
| **10-IndexAccountHistory** | Prometheus `rate(reth_sync_checkpoint{stage="IndexAccountHistory"}[5m])` | Prometheus `reth_sync_checkpoint` | Block-based |
| **11-Prune** | Prometheus `rate(reth_sync_checkpoint{stage="Prune"}[5m])` | Prometheus `reth_sync_checkpoint` | Block-based |
| **12-Finish** | Prometheus `rate(reth_sync_checkpoint{stage="Finish"}[5m])` | Prometheus `reth_sync_checkpoint` | Block-based |

### Dashboard Implementation Notes

1. **StorageHashing**: Use log-based `checkpoint` for real-time visibility (~25s updates). For ETA, use historical rate of ~21 blocks/s.

2. **MerkleExecute**: Use log-based `checkpoint` for checkpoint, and `stage_eta` label for ETA (the only stage with native ETA in logs).

3. **Log-based metrics are DELTA counters**: The metric counts log entries. Labels like `checkpoint`, `stage_eta` are STRING values that can be displayed in table columns but cannot be used in arithmetic.

4. **VM filter pattern**: Use `vm_name=~"op-reth.*|c4-.*"` to match both naming conventions.

---

## ETA Calculation Methods

### Method 1: Rate-Based (for active stages)

When a stage is actively processing, use its rate:

```
ETA (seconds) = blocks_remaining / rate(checkpoint)
```

**Limitations:** Returns infinity/NaN when rate is 0 (stage not active).

### Method 2: Historical Time Ratio (for pending stages)

Use completed stage times to estimate pending stages:

```
ETA (seconds) = (blocks_remaining / blocks_completed) * historical_time
```

**Example:** If AccountHashing took 1,677 seconds for 525K blocks:
- Rate = 525,304 / 1,677 = 313 blocks/second
- For 50K remaining blocks: 50,000 / 313 = 160 seconds

### Method 3: Cross-VM Reference (for stages not yet started)

Use data from a VM that has completed the stage:

```
ETA = blocks_remaining * (reference_vm_time / reference_vm_blocks)
```

### Method 4: Entity-Based Estimation

For stages with meaningful entity counts:

```
ETA = entities_remaining / rate(entities_processed)
```

**Works for:** Execution (gas), AccountHashing (accounts), SenderRecovery (transactions)

---

## PromQL Queries

### Current Stage Detection

```promql
# Stages with non-zero processing rate (active)
rate(reth_sync_checkpoint[5m]) > 0

# Find the bottleneck stage (lowest checkpoint, excluding online stages)
min without(stage) (reth_sync_checkpoint{stage!~"Headers|Bodies|SenderRecovery"})

# Gap between Execution and hashing stages
reth_sync_checkpoint{stage="Execution"} - reth_sync_checkpoint{stage="StorageHashing"}
```

### Execution Stage ETA

```promql
# ETA in hours based on blocks remaining and gas throughput
# Assumes ~30M gas per block average for Base L2
(max(op_node_default_refs_number{layer="l2",type="l2_unsafe"}) - reth_sync_checkpoint{stage="Execution"}) 
  / (reth_sync_execution_gas_per_second / 30000000) / 3600

# Alternative: rate-based (only works when Execution is active)
(max(op_node_default_refs_number{layer="l2",type="l2_unsafe"}) - reth_sync_checkpoint{stage="Execution"}) 
  / rate(reth_sync_checkpoint{stage="Execution"}[15m]) / 3600
```

### Hashing Stages ETA

```promql
# Blocks in hashing queue
reth_sync_checkpoint{stage="Execution"} - reth_sync_checkpoint{stage="StorageHashing"}

# StorageHashing ETA based on historical rate (21 blocks/s from benchmark)
(reth_sync_checkpoint{stage="Execution"} - reth_sync_checkpoint{stage="StorageHashing"}) / 21 / 3600

# MerkleExecute ETA based on historical rate (30 blocks/s from benchmark)
(reth_sync_checkpoint{stage="StorageHashing"} - reth_sync_checkpoint{stage="MerkleExecute"}) / 30 / 3600
```

### History Indexing ETA

```promql
# TransactionLookup ETA based on historical rate (50 blocks/s from benchmark)
(reth_sync_checkpoint{stage="MerkleExecute"} - reth_sync_checkpoint{stage="TransactionLookup"}) / 50 / 3600
```

### Overall Sync ETA

```promql
# Total blocks behind (from Finish stage to chain tip)
max(op_node_default_refs_number{layer="l2",type="l2_unsafe"}) - reth_sync_checkpoint{stage="Finish"}

# Overall ETA when Finish stage is progressing
(max(op_node_default_refs_number{layer="l2",type="l2_unsafe"}) - reth_sync_checkpoint{stage="Finish"}) 
  / rate(reth_sync_checkpoint{stage="Finish"}[15m]) / 3600
```

### Time Spent Per Stage

```promql
# Time in each stage (hours)
reth_sync_total_elapsed / 3600

# Execution time specifically
reth_sync_total_elapsed{stage="Execution"} / 3600

# Percentage of time in each stage
reth_sync_total_elapsed / ignoring(stage) group_left sum(reth_sync_total_elapsed) * 100
```

---

## Historical Benchmarks

### Benchmark: 525K Block Sync (Block 40.8M → 41.4M)

Data collected from `op-reth-c3-standard-176-lssd-notdx` (c3-standard-176, NVMe RAID-0, no TDX):

| Stage | Time (seconds) | Time (hours) | Rate (blocks/s) | % of Total |
|-------|----------------|--------------|-----------------|------------|
| Headers | 61 | 0.02 | 8,611 | <1% |
| Bodies | 463 | 0.13 | 1,134 | <1% |
| SenderRecovery | 87 | 0.02 | 6,038 | <1% |
| **Execution** | 41,599 | 11.56 | 12.6 | 42% |
| AccountHashing | 1,677 | 0.47 | 313 | 2% |
| **StorageHashing** | 24,978 | 6.94 | 21 | 25% |
| **MerkleExecute** | 17,267 | 4.80 | 30 | 17% |
| TransactionLookup | 10,524 | 2.92 | 50 | 11% |
| IndexStorageHistory | TBD | TBD | TBD | <1% |
| IndexAccountHistory | TBD | TBD | TBD | <1% |
| Prune | TBD | TBD | TBD | <1% |
| Finish | TBD | TBD | TBD | <1% |

**Total time for 525K blocks: ~27 hours**

### Reference Rates by Machine Type

| Machine Type | Storage | Execution (MGas/s) | StorageHashing (blk/s) | MerkleExecute (blk/s) |
|--------------|---------|--------------------|-----------------------|----------------------|
| c3-standard-176 (noTDX) | NVMe RAID-0 | 1,139 | 21 | 30 |
| c3-standard-176 (TDX) | NVMe RAID-0 | 700 | TBD | TBD |
| c3-standard-44 (noTDX) | pd-balanced | 496-552 | TBD | TBD |
| c3-standard-44 (TDX) | pd-balanced | 527-533 | TBD | TBD |
| c3-standard-44 | pd-ssd | 527-552 | TBD | TBD |

---

## Dashboard Implementation

### Recommended Widgets

#### 1. Current Stage Indicator

Show which stage each VM is in:

```promql
# The stage with the lowest checkpoint (excluding completed stages)
# This requires custom logic - see below
```

**Implementation approach:** Create a table showing all stages' checkpoints. The stage with a checkpoint less than its predecessor is the "current" stage.

#### 2. Stage Progress Table

| Column | Query |
|--------|-------|
| VM | `vm_name` label |
| Execution | `reth_sync_checkpoint{stage="Execution"}` |
| StorageHashing | `reth_sync_checkpoint{stage="StorageHashing"}` |
| MerkleExecute | `reth_sync_checkpoint{stage="MerkleExecute"}` |
| Finish | `reth_sync_checkpoint{stage="Finish"}` |

#### 3. Time Breakdown Chart

```promql
# Stacked time per stage
reth_sync_total_elapsed
```

#### 4. ETA Table (Estimated)

For stages with known rates, calculate ETA. For pending stages, show "Pending" or estimate based on historical rates.

```promql
# Combined ETA query (sum of all remaining stages)
# This is complex and may need to be split into multiple widgets
```

### Simplified ETA Widget

Given the complexity, a practical approach is:

1. **For VMs in Execution:** Show Execution ETA
2. **For VMs in Hashing:** Show estimated hashing time based on blocks remaining
3. **For VMs in History:** Show estimated completion time

```promql
# Execution ETA (when active)
(max(op_node_default_refs_number{layer="l2",type="l2_unsafe"}) - reth_sync_checkpoint{stage="Execution"}) 
  / rate(reth_sync_checkpoint{stage="Execution"}[15m]) / 3600

# Hashing ETA (blocks in queue / historical rate)
# Using 21 blocks/s as StorageHashing rate, 30 blocks/s for MerkleExecute
((reth_sync_checkpoint{stage="Execution"} - reth_sync_checkpoint{stage="StorageHashing"}) / 21 
 + (reth_sync_checkpoint{stage="StorageHashing"} - reth_sync_checkpoint{stage="MerkleExecute"}) / 30) / 3600

# History ETA (50 blocks/s rate)
(reth_sync_checkpoint{stage="MerkleExecute"} - reth_sync_checkpoint{stage="Finish"}) / 50 / 3600
```

---

## Future Improvements

### 1. Dynamic Rate Calculation

Instead of hardcoded rates, calculate rates dynamically from VMs that are actively in each stage:

```promql
# Get StorageHashing rate from VMs where it's active
avg(rate(reth_sync_checkpoint{stage="StorageHashing"}[5m])) > 0
```

### 2. Per-VM Historical Rates

Store historical rates per machine type in a ConfigMap or Terraform variable, then reference them in dashboard queries.

### 3. Weighted ETA

Weight the ETA by stage importance:

```
Total ETA = Execution_ETA + (Hashing_ETA * 1.0) + (History_ETA * 0.5)
```

### 4. Recording Rules

Create Prometheus recording rules to pre-calculate complex metrics:

```yaml
groups:
  - name: reth_eta
    rules:
      - record: reth:sync:eta:execution_hours
        expr: |
          (max(op_node_default_refs_number{layer="l2",type="l2_unsafe"}) - reth_sync_checkpoint{stage="Execution"}) 
          / rate(reth_sync_checkpoint{stage="Execution"}[15m]) / 3600
```

### 5. Log-Based Metrics for Real-Time Stage Progress

**Problem:** Prometheus metrics (`reth_sync_checkpoint`) only update when a stage commits at the end of a batch. During long-running stages like StorageHashing (7+ hours), there's no progress visibility in metrics.

**Solution:** Extract real-time stage information from op-reth logs using Cloud Logging log-based metrics.

#### Available Log Data

op-reth emits status logs every ~25 seconds:

```
INFO Status connected_peers=19 stage=StorageHashing checkpoint=40840749 target=41368260
```

| Field | Description | Use |
|-------|-------------|-----|
| `stage` | Current pipeline stage | Know which stage VM is in |
| `checkpoint` | Progress within current batch | Calculate stage progress % |
| `target` | Target block for batch | Calculate blocks remaining |

**Note:** Current logs include ANSI escape codes which complicate regex extraction.

#### Implementation Steps

1. **Disable ANSI colors** (prerequisite)
   - Add `Environment="NO_COLOR=1"` to `op-reth.service.j2`
   - Requires service restart on existing VMs

2. **Create log-based metrics** (Terraform)
   - Filter: `textPayload=~"Status.*stage="`
   - Extract labels: `stage`, `vm_name`
   - Extract values: `checkpoint`, `target`

3. **Update dashboard**
   - Add "Current Stage" widget from log-based metrics
   - Add "Stage Progress %" widget

#### Regex Patterns

With ANSI codes (current logs):
```regex
stage[^=]*=[^A-Za-z]*(\w+).*checkpoint[^=]*=[^0-9]*(\d+).*target[^=]*=[^0-9]*(\d+)
```

Without ANSI codes (after fix):
```regex
stage=(\w+).*checkpoint=(\d+).*target=(\d+)
```

#### Limitations

- Log-based metrics have ~1 minute latency
- Log-based metrics are counters/distributions, not gauges (need workarounds for latest value)
- Alternative: Use Log Analytics SQL queries directly in dashboard

#### Status: IMPLEMENTED

- [x] Log-based metric `reth_stage_log_count` created in `terraform/modules/monitoring/main.tf`
- [x] Labels extracted: `vm_name`, `stage`, `checkpoint`, `target`, `stage_progress`, `stage_eta`
- [x] Works without disabling ANSI colors (regex handles both formats)
- [ ] Dashboard v3 with per-stage breakdown (in progress)

---

## Appendix: Raw Data Collection

To collect metrics from a running VM for benchmarking:

```bash
# SSH to VM and get all sync metrics
gcloud compute ssh VM_NAME \
  --project PROJECT_ID \
  --zone ZONE \
  -- -o Hostname=nic0.VM_NAME.ZONE.c.PROJECT_ID.internal.gcpnode.com \
  "curl -s http://localhost:9001/metrics | grep -E 'reth_sync_checkpoint|reth_sync_entities|reth_sync_total_elapsed' | sort"

# Get L2 chain tip from op-node
gcloud compute ssh VM_NAME \
  --project PROJECT_ID \
  --zone ZONE \
  -- -o Hostname=nic0.VM_NAME.ZONE.c.PROJECT_ID.internal.gcpnode.com \
  "curl -s http://localhost:7300/metrics | grep 'op_node_default_refs_number.*l2_unsafe'"
```

---

## References

- [PERFORMANCE-TUNING.md](PERFORMANCE-TUNING.md) - Performance tuning and bottleneck detection
- [AGENTS.md](../AGENTS.md) - Dashboard PromQL queries and gotchas
- [Reth Metrics Source](https://github.com/paradigmxyz/reth/tree/main/crates/stages/api/src/metrics) - Stage metrics implementation
