# =============================================================================
# Cloud Build Private Pool Module - Outputs
# =============================================================================

output "pool_name" {
  description = "Full resource name for Cloud Build options.pool.name"
  value       = "projects/${var.project_id}/locations/${var.region}/workerPools/${google_cloudbuild_worker_pool.pool.name}"
}

output "pool_id" {
  description = "Worker pool ID"
  value       = google_cloudbuild_worker_pool.pool.id
}
