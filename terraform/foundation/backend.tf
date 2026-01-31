# =============================================================================
# Foundation Backend Configuration
# =============================================================================
# Stores state in GCS bucket under terraform/foundation/

terraform {
  backend "gcs" {
    bucket = "base-mainnet-snapshot"
    prefix = "terraform/foundation"
  }
}
