# =============================================================================
# Foundation Module Outputs
# =============================================================================

output "service_account_email" {
  description = "Email of the benchmark service account"
  value       = google_service_account.benchmark.email
}

output "service_account_id" {
  description = "ID of the benchmark service account"
  value       = google_service_account.benchmark.id
}

output "cloudbuild_pool_id" {
  description = "ID of the Cloud Build worker pool"
  value       = google_cloudbuild_worker_pool.pool.id
}

output "cloudbuild_pool_name" {
  description = "Name of the Cloud Build worker pool"
  value       = google_cloudbuild_worker_pool.pool.name
}
