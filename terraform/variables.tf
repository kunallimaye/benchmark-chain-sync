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
# Reth Configuration
# -----------------------------------------------------------------------------
variable "reth_batch_size" {
  type        = number
  default     = 10000
  description = "Number of blocks per execution batch. Lower values = more frequent checkpoints."
}

variable "reth_batch_duration" {
  type        = string
  default     = "1m"
  description = "Maximum duration per batch (e.g., '1m', '30s'). Limits time between checkpoints."
}

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
