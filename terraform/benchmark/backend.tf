# =============================================================================
# Benchmark Backend Configuration
# =============================================================================
# Stores state in GCS bucket under terraform/benchmark/

terraform {
  backend "gcs" {
    bucket = "base-mainnet-snapshot"
    prefix = "terraform/benchmark"
  }
}
