# =============================================================================
# Benchmark Module Variables
# =============================================================================

variable "name" {
  type        = string
  description = "Instance name (e.g., op-reth-c3-standard-44-pd-balanced)"
}

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "zone" {
  type        = string
  description = "GCP zone"
}

variable "machine_type" {
  type        = string
  description = "GCE machine type"
}

variable "storage_type" {
  type        = string
  default     = null
  nullable    = true
  description = "Storage type: pd-standard, pd-balanced, pd-ssd, hyperdisk-balanced, hyperdisk-extreme, or null for LSSD machine types."

  validation {
    condition = var.storage_type == null ? true : contains([
      "pd-standard", "pd-balanced", "pd-ssd",
      "hyperdisk-balanced", "hyperdisk-extreme"
    ], var.storage_type)
    error_message = "storage_type must be null (for LSSD), pd-standard, pd-balanced, pd-ssd, hyperdisk-balanced, or hyperdisk-extreme"
  }
}

variable "disk_size_gb" {
  type        = number
  default     = 15000
  description = "Disk size in GB (only applies to persistent disks, ignored for LSSD)"
}

variable "provisioned_iops" {
  type        = number
  default     = null
  nullable    = true
  description = "Provisioned IOPS (required for Hyperdisk types)"
}

variable "provisioned_throughput" {
  type        = number
  default     = null
  nullable    = true
  description = "Provisioned throughput in MB/s (required for Hyperdisk types)"
}

variable "reth_version" {
  type        = string
  description = "Reth version (tag or commit SHA)"
}

variable "service_account_email" {
  type        = string
  description = "Service account email for the VM"
}

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

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Labels to apply to resources"
}

variable "mount_point" {
  type        = string
  default     = "/mnt/data"
  description = "Mount point for the data disk"
}

variable "snapshot_name" {
  type        = string
  default     = ""
  description = "Name of GCP snapshot to create disk from (empty = create blank disk, which will fail without data)"
}

variable "snapshot_disk_size_gb" {
  type        = number
  default     = 12000
  description = "Size of disk created from snapshot (in GB)"
}
