# =============================================================================
# Snapshots Module - Golden Snapshot Management
# =============================================================================
# This module manages golden snapshots used for fast VM provisioning.
# Snapshots are created from fully synced VMs and used to quickly spin up
# new benchmark instances.
#
# Note: Snapshot creation/deletion is handled by Cloud Build pipelines
# rather than Terraform to allow for VM-level operations (stopping VMs, etc.)
# =============================================================================

# -----------------------------------------------------------------------------
# Data source for existing snapshots (for reference)
# -----------------------------------------------------------------------------
data "google_compute_snapshot" "golden" {
  count   = var.snapshot_name != "" ? 1 : 0
  name    = var.snapshot_name
  project = var.project_id
}

# Output information about the current golden snapshot
locals {
  snapshot_exists = length(data.google_compute_snapshot.golden) > 0
  snapshot_info = local.snapshot_exists ? {
    name         = data.google_compute_snapshot.golden[0].name
    self_link    = data.google_compute_snapshot.golden[0].self_link
    disk_size_gb = data.google_compute_snapshot.golden[0].disk_size_gb
    created      = data.google_compute_snapshot.golden[0].creation_timestamp
    status       = data.google_compute_snapshot.golden[0].storage_bytes > 0 ? "READY" : "UPLOADING"
    storage_gb   = data.google_compute_snapshot.golden[0].storage_bytes / 1073741824
  } : null
}
