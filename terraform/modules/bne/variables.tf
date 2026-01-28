# =============================================================================
# Blockchain Node Engine (BNE) Module - Variables
# =============================================================================

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region for the BNE node"
}

variable "l1_network" {
  type        = string
  description = "L1 Ethereum network: MAINNET or HOLESKY"

  validation {
    condition     = contains(["MAINNET", "HOLESKY"], var.l1_network)
    error_message = "l1_network must be 'MAINNET' or 'HOLESKY'"
  }
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Labels to apply to the BNE node"
}
