# =============================================================================
# Snapshots Module Outputs
# =============================================================================

output "snapshot_info" {
  description = "Information about the golden snapshot"
  value       = local.snapshot_info
}

output "snapshot_name" {
  description = "Name of the golden snapshot"
  value       = local.snapshot_exists ? local.snapshot_info.name : null
}

output "snapshot_self_link" {
  description = "Self-link of the golden snapshot (for creating disks)"
  value       = local.snapshot_exists ? local.snapshot_info.self_link : null
}

output "snapshot_disk_size_gb" {
  description = "Disk size of the golden snapshot in GB"
  value       = local.snapshot_exists ? local.snapshot_info.disk_size_gb : null
}
