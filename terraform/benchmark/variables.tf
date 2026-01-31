# =============================================================================
# Benchmark Module Variables
# =============================================================================

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region"
  default     = "us-central1"
}

variable "network" {
  type        = string
  description = "VPC network for VMs"
  default     = "default"
}

variable "reth_version" {
  type        = string
  description = "Reth version (tag or commit SHA) for labeling VMs"
}

variable "service_account_email" {
  type        = string
  description = "Service account email for benchmark VMs"
}

variable "snapshot_name" {
  type        = string
  description = "Golden snapshot name to create disks from"
}

variable "snapshot_disk_size_gb" {
  type        = number
  description = "Size of disk created from snapshot (in GB)"
  default     = 12000
}
