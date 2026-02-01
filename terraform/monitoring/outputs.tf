# =============================================================================
# Monitoring Module Outputs
# =============================================================================

output "dashboard_id" {
  value       = google_monitoring_dashboard.reth_benchmark.id
  description = "Dashboard resource ID"
}

output "dashboard_url" {
  value       = "https://console.cloud.google.com/monitoring/dashboards/builder/${split("/", google_monitoring_dashboard.reth_benchmark.id)[3]}?project=${var.project_id}"
  description = "URL to view the dashboard in Cloud Console"
}
