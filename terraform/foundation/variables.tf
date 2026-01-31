# =============================================================================
# Foundation Module Variables
# =============================================================================

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region"
}

variable "network" {
  type        = string
  description = "VPC network name"
}

variable "gcs_bucket" {
  type        = string
  description = "GCS bucket for artifacts and state"
}
