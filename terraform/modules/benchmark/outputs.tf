# =============================================================================
# Benchmark Module Outputs
# =============================================================================

output "vm_name" {
  description = "Name of the VM instance"
  value       = google_compute_instance.vm.name
}

output "external_ip" {
  description = "External IP of the VM"
  value       = google_compute_instance.vm.network_interface[0].access_config[0].nat_ip
}

output "internal_ip" {
  description = "Internal IP of the VM"
  value       = google_compute_instance.vm.network_interface[0].network_ip
}

output "zone" {
  description = "Zone where the VM is located"
  value       = google_compute_instance.vm.zone
}

output "disk_name" {
  description = "Name of the data disk (null for local-ssd or LSSD machine types)"
  value       = local.create_persistent_disk ? google_compute_disk.data[0].name : null
}

output "reth_version" {
  description = "Reth version running on this instance"
  value       = var.reth_version
}

output "machine_type" {
  description = "Machine type of this instance"
  value       = var.machine_type
}

output "storage_type" {
  description = "Storage type of this instance"
  value       = var.storage_type
}

output "confidential_compute" {
  description = "Whether TDX confidential compute is enabled"
  value       = var.confidential_compute
}

output "is_lssd_machine" {
  description = "Whether this is an LSSD machine (requires rsync for data)"
  value       = local.is_lssd_machine
}
