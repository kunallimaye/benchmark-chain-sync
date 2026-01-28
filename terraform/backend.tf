# =============================================================================
# Terraform Backend Configuration
# =============================================================================
# State is stored in GCS bucket.
# Backend config is partially specified here; bucket and prefix are passed
# via -backend-config flags during terraform init.
# =============================================================================

terraform {
  backend "gcs" {
    # bucket and prefix are passed via:
    #   terraform init \
    #     -backend-config="bucket=base-mainnet-snapshot" \
    #     -backend-config="prefix=terraform/state/${VARIANT}"
  }
}
