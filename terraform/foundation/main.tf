# =============================================================================
# Foundation Module - APIs, IAM, and Cloud Build Pool
# =============================================================================
# This module sets up the foundational infrastructure that rarely changes:
# - GCP APIs
# - Service Account for benchmark VMs
# - Cloud Build private worker pool for SSH access
# =============================================================================

# -----------------------------------------------------------------------------
# Enable Required GCP APIs
# -----------------------------------------------------------------------------
resource "google_project_service" "compute" {
  project            = var.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "storage" {
  project            = var.project_id
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iam" {
  project            = var.project_id
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "monitoring" {
  project            = var.project_id
  service            = "monitoring.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "logging" {
  project            = var.project_id
  service            = "logging.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudresourcemanager" {
  project            = var.project_id
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "serviceusage" {
  project            = var.project_id
  service            = "serviceusage.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudbuild" {
  project            = var.project_id
  service            = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "servicenetworking" {
  project            = var.project_id
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudtrace" {
  project            = var.project_id
  service            = "cloudtrace.googleapis.com"
  disable_on_destroy = false
}

# -----------------------------------------------------------------------------
# Service Account for Benchmark VMs
# -----------------------------------------------------------------------------
resource "google_service_account" "benchmark" {
  account_id   = "op-reth-benchmark"
  display_name = "Shared service account for op-reth benchmark VMs"
  project      = var.project_id

  depends_on = [google_project_service.iam]
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

# Grant Cloud Trace agent for OTLP tracing
resource "google_project_iam_member" "trace_agent" {
  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${google_service_account.benchmark.email}"
}

# -----------------------------------------------------------------------------
# Cloud Build Private Worker Pool
# -----------------------------------------------------------------------------
# Creates a private worker pool with VPC peering to enable SSH access to VMs

resource "google_compute_global_address" "cloudbuild_pool_range" {
  name          = "cloudbuild-pool-range"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 24
  network       = "projects/${var.project_id}/global/networks/${var.network}"

  depends_on = [google_project_service.compute]
}

resource "google_service_networking_connection" "cloudbuild_pool" {
  network                 = "projects/${var.project_id}/global/networks/${var.network}"
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.cloudbuild_pool_range.name]

  depends_on = [google_project_service.servicenetworking]
}

resource "google_cloudbuild_worker_pool" "pool" {
  name     = "benchmark-build-pool"
  location = var.region
  project  = var.project_id

  worker_config {
    disk_size_gb   = 100
    machine_type   = "e2-standard-4"
    no_external_ip = false
  }

  network_config {
    peered_network          = "projects/${var.project_id}/global/networks/${var.network}"
    peered_network_ip_range = "/29"
  }

  depends_on = [
    google_project_service.cloudbuild,
    google_service_networking_connection.cloudbuild_pool
  ]
}
