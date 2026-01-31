# =============================================================================
# Monitoring Backend Configuration
# =============================================================================
# Stores state in GCS bucket under terraform/monitoring/

terraform {
  backend "gcs" {
    bucket = "base-mainnet-snapshot"
    prefix = "terraform/monitoring"
  }
}
