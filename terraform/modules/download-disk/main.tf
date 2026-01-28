# =============================================================================
# Download Disk Module - Shared snapshot storage
# =============================================================================
# Creates a persistent disk for storing downloaded snapshots.
# This disk is shared read-only across all benchmark VMs for extraction.
# Download once, extract many times.
# =============================================================================

resource "google_compute_disk" "download" {
  name    = var.name
  type    = var.disk_type
  size    = var.disk_size_gb
  zone    = var.zone
  project = var.project_id

  labels = merge(var.labels, {
    purpose = "snapshot-download"
  })

  lifecycle {
    # SAFETY: Prevent accidental deletion of download disk
    # This disk contains the downloaded snapshot which takes hours to download.
    # To delete, you must first remove this lifecycle rule.
    prevent_destroy = true
  }
}
