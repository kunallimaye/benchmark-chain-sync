# Pruning a Reth Archive Node for Quick Benchmarks

This document describes how to prune an existing archive node to create a smaller "quick-bench" snapshot for faster benchmark provisioning.

## Overview

| Metric | Archive Node | Pruned Node |
|--------|--------------|-------------|
| Disk size | ~8TB | ~100-200GB |
| Provision time | 15+ min (pd), 3+ hours (LSSD) | ~2-3 min |
| History | Full chain history | Last 1M blocks |
| Use case | Full benchmarks, tracing | Quick iteration, performance tests |

## Background

### Reth Node Types

| Type | Description | Can Convert? |
|------|-------------|--------------|
| **Archive** | Default, keeps all history | - |
| **Full** (`--full` flag) | Predefined pruning, last 10064 blocks | No (set at genesis) |
| **Pruned** | Custom pruning via `[prune]` config | Yes (via `op-reth prune`) |

### Key Insight

While the docs say "node type cannot be changed after initial sync", this refers to the `--full` flag. The `op-reth prune` command can perform a **one-time prune** of an existing archive node.

## Prune Configuration

Add to `reth.toml` to keep only the last 1M blocks:

```toml
# -----------------------------------------------------------------------------
# Prune Configuration (Quick Benchmark)
# -----------------------------------------------------------------------------
# Keep only the last 1M blocks of history for fast provisioning
# Reduces disk from ~8TB to ~100-200GB
# -----------------------------------------------------------------------------
[prune]
block_interval = 5

[prune.segments]
sender_recovery = "full"                    # Prune all (saves ~85GB)
transaction_lookup = "full"                 # Prune all (saves ~200GB)
receipts = { distance = 1_000_000 }         # Keep last 1M blocks
account_history = { distance = 1_000_000 }  # Keep last 1M blocks
storage_history = { distance = 1_000_000 }  # Keep last 1M blocks
```

### Prune Distance Options

| Distance | Approx Size | History Kept |
|----------|-------------|--------------|
| 500,000 | ~50-100GB | ~1 day |
| 1,000,000 | ~100-200GB | ~2-3 days |
| 2,000,000 | ~200-400GB | ~5-6 days |

## Procedure

### Step 1: Stop Services

```bash
gcloud compute ssh <VM_NAME> --project=<PROJECT> --zone=<ZONE> -- \
  -o Hostname=nic0.<VM_NAME>.<ZONE>.c.<PROJECT>.internal.gcpnode.com \
  "sudo systemctl stop op-reth op-node && sudo systemctl status op-reth op-node"
```

### Step 2: Add Prune Configuration

Append the prune config (above) to `/mnt/data/op-reth/reth.toml`.

### Step 3: Run `op-reth prune`

Run the one-time prune command:

```bash
# SSH to VM
gcloud compute ssh <VM_NAME> ...

# Run prune with nohup (survives SSH disconnect)
sudo -u reth nohup op-reth prune \
  --chain base \
  --datadir /mnt/data/op-reth \
  --config /mnt/data/op-reth/reth.toml \
  -vvv \
  > /tmp/prune.log 2>&1 &

# Monitor progress
tail -f /tmp/prune.log

# Check disk size periodically
watch -n 60 'du -sh /mnt/data/op-reth/'
```

**Expected time:** 1-8 hours (unknown, depends on data size)

### Step 4: Verify Pruning

After prune completes:

```bash
# Check disk size (target: ~100-200GB)
du -sh /mnt/data/op-reth/
du -sh /mnt/data/op-reth/db/
du -sh /mnt/data/op-reth/static_files/

# Check logs for errors
tail -50 /tmp/prune.log
```

### Step 5: Test Node Starts

```bash
# Start node
sudo systemctl start op-reth

# Verify logs (look for errors)
sudo journalctl -u op-reth -f --no-pager | head -100

# Test RPC
curl -s -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8545

# Stop for snapshot
sudo systemctl stop op-reth op-node
```

### Step 6: Create Quick-Bench Snapshot

```bash
gcloud compute snapshots create op-reth-quick-bench-$(date +%Y-%m-%d-%H-%M) \
  --source-disk=<VM_NAME>-data \
  --source-disk-zone=<ZONE> \
  --storage-location=<REGION> \
  --project=<PROJECT>
```

**Time:** ~5-10 min for 100-200GB

### Step 7: Test Quick Benchmark Workflow

```bash
# Create test disk from snapshot (time this - should be ~2-3 min)
time gcloud compute disks create quick-bench-test-disk \
  --source-snapshot=op-reth-quick-bench-YYYY-MM-DD-HH-MM \
  --zone=<ZONE> \
  --type=pd-ssd \
  --project=<PROJECT>

# Cleanup
gcloud compute disks delete quick-bench-test-disk --zone=<ZONE> --project=<PROJECT> --quiet
```

## Debug Options for Benchmarks

When running benchmarks, use these flags to control sync behavior:

| Option | Purpose | Example |
|--------|---------|---------|
| `--debug.max-block <N>` | Stop sync at block N | `--debug.max-block 41000000` |
| `--debug.tip <HASH>` | Sync to specific block hash | `--debug.tip 0x123...` |
| `--debug.terminate` | Exit after pipeline sync completes | (no value) |

### Example Benchmark Run

```bash
op-reth node \
  --chain base \
  --datadir /mnt/data/op-reth \
  --debug.max-block 41000000 \
  --debug.terminate
```

This will:
1. Sync from current checkpoint to block 41M
2. Run all pipeline stages to completion
3. Exit automatically when done

## Success Criteria

| Check | Expected |
|-------|----------|
| Disk size after prune | ~100-200GB |
| Node starts without errors | Yes |
| RPC returns block number | ~40M+ |
| Snapshot creation time | ~5-10 min |
| Disk from snapshot time | ~2-3 min |

## Troubleshooting

### Prune command fails

Check logs for specific error:
```bash
cat /tmp/prune.log | grep -i error
```

Common issues:
- Database locked: ensure op-reth service is stopped
- Permission denied: run as reth user (`sudo -u reth`)
- Out of disk space: pruning may temporarily need extra space

### Node fails to start after prune

Check for database corruption:
```bash
op-reth db stats --chain base --datadir /mnt/data/op-reth
```

If corrupted, restore from the golden snapshot and retry.

### Disk size not reduced

Static files may not be pruned. Check:
```bash
du -sh /mnt/data/op-reth/static_files/*
```

Static files are immutable segments; they may require manual cleanup or a fresh sync with pruning enabled from the start.

## References

- [Reth Pruning Docs](https://reth.rs/run/faq/pruning)
- [Reth Configuration](https://reth.rs/run/configuration#the-prune-section)
- [op-reth prune CLI](https://reth.rs/cli/op-reth/prune)
