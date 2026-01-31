# =============================================================================
# L1 Backend Configuration
# =============================================================================
# Stores state in GCS bucket under terraform/l1/
# 
# IMPORTANT: State was migrated from terraform/state/l1-base-mainnet/ to terraform/l1/
# The existing l1-mainnet BNE node is tracked in this state.

terraform {
  backend "gcs" {
    bucket = "base-mainnet-snapshot"
    prefix = "terraform/l1"
  }
}
