# =============================================================================
# Snapshots Module Variables
# =============================================================================

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "snapshot_name" {
  type        = string
  description = "Name of the golden snapshot to reference"
  default     = ""
}
