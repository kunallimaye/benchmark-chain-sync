# =============================================================================
# IAM Module Outputs
# =============================================================================

output "service_account_email" {
  description = "Email of the shared service account"
  value       = google_service_account.benchmark.email
}

output "service_account_id" {
  description = "ID of the shared service account"
  value       = google_service_account.benchmark.id
}
