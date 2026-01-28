# =============================================================================
# IAM Module - Shared Service Account for all benchmark VMs
# =============================================================================

resource "google_service_account" "benchmark" {
  account_id   = "op-reth-benchmark"
  display_name = "Shared service account for op-reth benchmark VMs"
  project      = var.project_id
}

# Grant access to GCS bucket for downloading artifacts and snapshots
resource "google_storage_bucket_iam_member" "bucket_reader" {
  bucket = var.gcs_bucket
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.benchmark.email}"
}

# Grant write access for uploading results
resource "google_storage_bucket_iam_member" "bucket_writer" {
  bucket = var.gcs_bucket
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.benchmark.email}"
}

# Grant monitoring metrics writer for Ops Agent
resource "google_project_iam_member" "metrics_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.benchmark.email}"
}

# Grant logging writer for Ops Agent
resource "google_project_iam_member" "logs_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.benchmark.email}"
}

# NOTE: The serviceAccountTokenCreator role is applied manually (not via Terraform)
# because Cloud Build doesn't have iam.serviceAccounts.setIamPolicy permission.
# See AGENTS.md "Manual IAM Setup" section for the one-time setup command.
