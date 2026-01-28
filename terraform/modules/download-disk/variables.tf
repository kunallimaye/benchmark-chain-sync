# =============================================================================
# Download Disk Module Variables
# =============================================================================

variable "name" {
  type        = string
  description = "Name for the download disk"
}

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "zone" {
  type        = string
  description = "GCP zone"
}

variable "disk_size_gb" {
  type        = number
  default     = 8000
  description = "Disk size in GB (should be larger than compressed snapshot)"
}

variable "disk_type" {
  type        = string
  default     = "pd-balanced"
  description = "Disk type: pd-standard, pd-balanced, pd-ssd"

  validation {
    condition     = contains(["pd-standard", "pd-balanced", "pd-ssd"], var.disk_type)
    error_message = "disk_type must be pd-standard, pd-balanced, or pd-ssd"
  }
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Labels to apply to the disk"
}
