# =============================================================================
# IAM Module Variables
# =============================================================================

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "gcs_bucket" {
  type        = string
  description = "GCS bucket name for artifact access"
}
