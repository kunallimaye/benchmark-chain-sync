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

output "dashboard_v3_id" {
  value       = google_monitoring_dashboard.reth_benchmark_v3.id
  description = "Dashboard resource ID (v3 - per-stage breakdown)"
}

output "dashboard_v3_url" {
  value       = "https://console.cloud.google.com/monitoring/dashboards/builder/${split("/", google_monitoring_dashboard.reth_benchmark_v3.id)[3]}?project=${var.project_id}"
  description = "URL to view the v3 dashboard (per-stage breakdown with 13 stages) in Cloud Console"
}

output "sync_status_dashboard_id" {
  value       = google_monitoring_dashboard.sync_status.id
  description = "Dashboard resource ID (sync status - real-time from logs)"
}

output "sync_status_dashboard_url" {
  value       = "https://console.cloud.google.com/monitoring/dashboards/builder/${split("/", google_monitoring_dashboard.sync_status.id)[3]}?project=${var.project_id}"
  description = "URL to view the Sync Status dashboard (real-time from logs) in Cloud Console"
}
