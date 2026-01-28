# =============================================================================
# APIs Module Outputs
# =============================================================================

output "enabled_apis" {
  description = "List of enabled API services"
  value = [
    google_project_service.compute.service,
    google_project_service.storage.service,
    google_project_service.iam.service,
    google_project_service.monitoring.service,
    google_project_service.logging.service,
    google_project_service.cloudresourcemanager.service,
    google_project_service.serviceusage.service,
  ]
}
