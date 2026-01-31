# =============================================================================
# Snapshots Backend Configuration
# =============================================================================
# Stores state in GCS bucket under terraform/snapshots/

terraform {
  backend "gcs" {
    bucket = "base-mainnet-snapshot"
    prefix = "terraform/snapshots"
  }
}
