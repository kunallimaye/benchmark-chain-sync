# =============================================================================
# L1 Module Variables
# =============================================================================

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region for the BNE node"
  default     = "us-central1"
}

variable "l1_network" {
  type        = string
  description = "L1 Ethereum network: MAINNET or HOLESKY"
  default     = "MAINNET"

  validation {
    condition     = contains(["MAINNET", "HOLESKY"], var.l1_network)
    error_message = "l1_network must be 'MAINNET' or 'HOLESKY'"
  }
}
