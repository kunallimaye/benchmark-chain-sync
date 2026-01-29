# =============================================================================
# Monitoring Module Outputs
# =============================================================================

output "dashboard_id" {
  value       = google_monitoring_dashboard.reth_benchmark.id
  description = "Dashboard resource ID (overview)"
}

output "dashboard_url" {
  value       = "https://console.cloud.google.com/monitoring/dashboards/builder/${split("/", google_monitoring_dashboard.reth_benchmark.id)[3]}?project=${var.project_id}"
  description = "URL to view the overview dashboard in Cloud Console"
}

output "dashboard_v1_id" {
  value       = google_monitoring_dashboard.reth_benchmark_v1.id
  description = "Dashboard resource ID (v1 - detailed stage analysis)"
}

output "dashboard_v1_url" {
  value       = "https://console.cloud.google.com/monitoring/dashboards/builder/${split("/", google_monitoring_dashboard.reth_benchmark_v1.id)[3]}?project=${var.project_id}"
  description = "URL to view the v1 dashboard (detailed stage analysis) in Cloud Console"
}
