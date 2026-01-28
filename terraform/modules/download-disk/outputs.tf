# =============================================================================
# Download Disk Module Outputs
# =============================================================================

output "disk_id" {
  value       = google_compute_disk.download.id
  description = "The ID of the download disk"
}

output "disk_name" {
  value       = google_compute_disk.download.name
  description = "The name of the download disk"
}

output "disk_self_link" {
  value       = google_compute_disk.download.self_link
  description = "The self_link of the download disk for attachment"
}

output "disk_size_gb" {
  value       = google_compute_disk.download.size
  description = "The size of the download disk in GB"
}
