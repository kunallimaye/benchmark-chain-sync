# =============================================================================
# Cloud Build Private Pool Module - Variables
# =============================================================================

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Region for the worker pool"
  type        = string
}

variable "network" {
  description = "VPC network name"
  type        = string
  default     = "default"
}

variable "pool_name" {
  description = "Name of the worker pool"
  type        = string
  default     = "benchmark-build-pool"
}
