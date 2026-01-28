# =============================================================================
# Cloud Build Private Pool Module
# =============================================================================
# Creates a Cloud Build private worker pool with VPC peering to enable
# SSH access to VMs via internal IP addresses.
# =============================================================================

# -----------------------------------------------------------------------------
# IP Range for VPC Peering
# -----------------------------------------------------------------------------
resource "google_compute_global_address" "cloudbuild_pool_range" {
  name          = "cloudbuild-pool-range"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 24
  network       = "projects/${var.project_id}/global/networks/${var.network}"
}

# -----------------------------------------------------------------------------
# VPC Peering Connection to Service Networking
# -----------------------------------------------------------------------------
resource "google_service_networking_connection" "cloudbuild_pool" {
  network                 = "projects/${var.project_id}/global/networks/${var.network}"
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.cloudbuild_pool_range.name]
}

# -----------------------------------------------------------------------------
# Cloud Build Private Worker Pool
# -----------------------------------------------------------------------------
resource "google_cloudbuild_worker_pool" "pool" {
  name     = var.pool_name
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

  depends_on = [google_service_networking_connection.cloudbuild_pool]
}
