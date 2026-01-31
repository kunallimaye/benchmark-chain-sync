# =============================================================================
# Terraform Variables
# =============================================================================

# -----------------------------------------------------------------------------
# Project & Location
# -----------------------------------------------------------------------------
variable "project_id" {
  type        = string
  default     = "bct-prod-c3-tdx-3"
  description = "GCP project ID"
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "GCP region"
}

variable "zone" {
  type        = string
  default     = "us-central1-a"
  description = "GCP zone"
}

# -----------------------------------------------------------------------------
# Network Configuration
# -----------------------------------------------------------------------------
variable "network" {
  type        = string
  default     = "base-mainnet"
  description = "Base network: base-mainnet or base-sepolia"

  validation {
    condition     = contains(["base-mainnet", "base-sepolia"], var.network)
    error_message = "Network must be 'base-mainnet' or 'base-sepolia'"
  }
}

# -----------------------------------------------------------------------------
# L1 Configuration (Blockchain Node Engine)
# -----------------------------------------------------------------------------
variable "create_l1" {
  type        = bool
  default     = false
  description = "Whether to create BNE resources (only for initial L1 setup)"
}

variable "l1_rpc_endpoint" {
  type        = string
  default     = null
  description = "L1 JSON-RPC endpoint URL (required when create_l1=false). Example: https://json-rpc.xxx.blockchainnodeengine.com"
}

variable "l1_beacon_endpoint" {
  type        = string
  default     = null
  description = "L1 Beacon API endpoint URL (required when create_l1=false). Example: https://beacon.xxx.blockchainnodeengine.com"
}

variable "l1_api_key" {
  type        = string
  sensitive   = true
  default     = null
  description = "API key for BNE access (passed at deploy time)"
}

# -----------------------------------------------------------------------------
# Golden Snapshot Configuration
# -----------------------------------------------------------------------------
variable "snapshot_name" {
  type        = string
  default     = ""
  description = "Name of GCP snapshot to create data disks from. Required for provisioning."
}

variable "snapshot_disk_size_gb" {
  type        = number
  default     = 12000
  description = "Size of data disks created from snapshot (in GB). Should be >= snapshot source disk actual data size."
}

# -----------------------------------------------------------------------------
# Benchmark Instances
# -----------------------------------------------------------------------------
variable "instances" {
  type = map(object({
    machine_type         = string
    storage_type         = optional(string)  # null for LSSD machine types
    disk_size_gb         = optional(number, 15000)
    reth_version         = string
    op_node_version      = optional(string, "v1.16.5")
    confidential_compute = optional(bool, true)
    # Performance tuning
    engine_cache_mb = optional(number, 4096)   # Cross-block cache size in MB
    engine_workers  = optional(number, 0)      # State root workers (0 = auto)
    # Node mode: "archive" or "full" (pruned)
    node_mode = optional(string, "archive")
    # Hyperdisk settings (only for hyperdisk-balanced/extreme)
    provisioned_iops       = optional(number)  # Required for Hyperdisk
    provisioned_throughput = optional(number)  # Required for Hyperdisk (MB/s)
  }))
  default     = {}
  description = "Map of benchmark instances to create. storage_type can be null for LSSD machine types."
}

# -----------------------------------------------------------------------------
# VM Defaults
# -----------------------------------------------------------------------------
variable "confidential_compute" {
  type        = bool
  default     = true
  description = "Enable TDX confidential compute"
}

variable "image_family" {
  type        = string
  default     = "ubuntu-2404-lts-amd64"
  description = "VM image family"
}

variable "image_project" {
  type        = string
  default     = "ubuntu-os-cloud"
  description = "VM image project"
}

# -----------------------------------------------------------------------------
# GCS Bucket
# -----------------------------------------------------------------------------
variable "gcs_bucket" {
  type        = string
  default     = "base-mainnet-snapshot"
  description = "GCS bucket for snapshots, artifacts, and state"
}

# -----------------------------------------------------------------------------
# Reth Configuration - Stage Thresholds
# -----------------------------------------------------------------------------
# Controls batch/commit thresholds for all pipeline stages.
# These are set to reth's default values for maximum sync performance.
# Reduce thresholds for more frequent checkpoint updates (better ETA visibility)
# at the cost of slower total sync time.
# -----------------------------------------------------------------------------

# Execution stage thresholds
variable "reth_execution_max_blocks" {
  type        = number
  default     = 500000
  description = "Blocks per execution batch (reth default: 500000)"
}

variable "reth_execution_max_changes" {
  type        = number
  default     = 5000000
  description = "State changes per batch (reth default: 5000000)"
}

variable "reth_execution_max_cumulative_gas" {
  type        = number
  default     = 1500000000000
  description = "Cumulative gas per batch (reth default: 1.5T)"
}

variable "reth_execution_max_duration" {
  type        = string
  default     = "10m"
  description = "Max duration per batch (reth default: 10m)"
}

# Headers stage
variable "reth_headers_commit_threshold" {
  type        = number
  default     = 10000
  description = "Blocks per commit for headers stage (reth default: 10000)"
}

# Sender Recovery stage
variable "reth_sender_recovery_commit_threshold" {
  type        = number
  default     = 5000000
  description = "Transactions per commit for sender recovery (reth default: 5000000)"
}

# Account Hashing stage
variable "reth_account_hashing_clean_threshold" {
  type        = number
  default     = 500000
  description = "Blocks before full re-hash for account hashing (reth default: 500000)"
}

variable "reth_account_hashing_commit_threshold" {
  type        = number
  default     = 100000
  description = "Entities per commit for account hashing (reth default: 100000)"
}

# Storage Hashing stage
variable "reth_storage_hashing_clean_threshold" {
  type        = number
  default     = 500000
  description = "Blocks before full re-hash for storage hashing (reth default: 500000)"
}

variable "reth_storage_hashing_commit_threshold" {
  type        = number
  default     = 100000
  description = "Entities per commit for storage hashing (reth default: 100000)"
}

# Merkle stage
variable "reth_merkle_incremental_threshold" {
  type        = number
  default     = 7000
  description = "Blocks for incremental Merkle computation (reth default: 7000)"
}

variable "reth_merkle_rebuild_threshold" {
  type        = number
  default     = 100000
  description = "Blocks before full Merkle trie rebuild (reth default: 100000)"
}

# Transaction Lookup stage
variable "reth_transaction_lookup_chunk_size" {
  type        = number
  default     = 5000000
  description = "Transactions per chunk for transaction lookup (reth default: 5000000)"
}

# Index History stages
variable "reth_index_account_history_commit_threshold" {
  type        = number
  default     = 100000
  description = "Blocks per commit for account history indexing (reth default: 100000)"
}

variable "reth_index_storage_history_commit_threshold" {
  type        = number
  default     = 100000
  description = "Blocks per commit for storage history indexing (reth default: 100000)"
}

# Prune stage
variable "reth_prune_commit_threshold" {
  type        = number
  default     = 1000000
  description = "Entries per commit for prune stage (reth default: 1000000)"
}

# ETL settings
variable "reth_etl_file_size" {
  type        = number
  default     = 524288000
  description = "ETL file size before flush (reth default: 500MB)"
}

# Database settings
variable "db_max_size_gb" {
  type        = number
  default     = 15000
  description = "Maximum database size in GB. Should be larger than expected final DB size."
}

variable "db_growth_step_mb" {
  type        = number
  default     = 4096
  description = "Database growth increment in MB. Larger values reduce mmap syscalls."
}

# -----------------------------------------------------------------------------
# Tracing Configuration
# -----------------------------------------------------------------------------
variable "tracing_enabled" {
  type        = bool
  default     = true
  description = "Enable OpenTelemetry tracing to Cloud Trace"
}

variable "tracing_sample_ratio" {
  type        = number
  default     = 0.01
  description = "Trace sampling ratio (0.0 to 1.0). Default 0.01 = 1% of traces"
}

variable "tracing_filter" {
  type        = string
  default     = "info"
  description = "Trace filter level: trace, debug, info, warn, error"
}

# -----------------------------------------------------------------------------
# Computed Locals
# -----------------------------------------------------------------------------
locals {
  # Mount points
  mount_point = "/mnt/data"

  # Build artifact path
  build_artifact_path = "gs://${var.gcs_bucket}/builds"

  # Map Base network to L1 Ethereum network
  l1_network_map = {
    "base-mainnet" = "MAINNET"
    "base-sepolia" = "HOLESKY"
  }
  l1_network = local.l1_network_map[var.network]

  # L1 labels
  l1_labels = {
    project    = "reth-benchmark"
    l1-network = lower(local.l1_network)
    managed-by = "terraform"
  }

  # Common labels for benchmark resources
  benchmark_labels = {
    project    = "reth-benchmark"
    network    = var.network
    managed-by = "terraform"
  }
}
