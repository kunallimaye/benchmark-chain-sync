# =============================================================================
# Benchmark VM Module - VM + Disk for a single benchmark instance
# =============================================================================

# Get the latest image from the specified family
data "google_compute_image" "vm_image" {
  family  = var.image_family
  project = var.image_project
}

# Startup script to format and mount disks
locals {
  # Detect if using built-in local SSD (explicit storage type)
  # This covers both -lssd and -metal machine types that have NVMe SSDs
  has_builtin_lssd = var.storage_type == "inbuilt-lssd"

  # Detect if using Hyperdisk (ternary to handle null before startswith)
  is_hyperdisk = var.storage_type != null ? startswith(var.storage_type, "hyperdisk-") : false

  # hyperdisk-extreme only supports IOPS, not throughput
  # hyperdisk-balanced and hyperdisk-throughput support both
  is_hyperdisk_extreme = var.storage_type == "hyperdisk-extreme"

  # Only create persistent disk if NOT using built-in local SSD
  create_persistent_disk = !local.has_builtin_lssd && var.storage_type != null

  # Storage type for labels (handle null case)
  storage_type_label = local.has_builtin_lssd ? "lssd" : coalesce(var.storage_type, "none")

  # Snapshot self-link for creating disk from snapshot
  snapshot_self_link = var.snapshot_name != "" ? "projects/${var.project_id}/global/snapshots/${var.snapshot_name}" : null

  startup_script = <<-EOF
    #!/bin/bash
    set -euo pipefail
    
    MOUNT_POINT="${var.mount_point}"
    MACHINE_TYPE="${var.machine_type}"
    STORAGE_TYPE="${coalesce(var.storage_type, "none")}"
    
    echo "=== Disk Setup Script ==="
    echo "Machine type: $MACHINE_TYPE"
    echo "Storage type: $STORAGE_TYPE"
    echo "Data mount point: $MOUNT_POINT"
    
    # =========================================================================
    # Mount Data Disk
    # =========================================================================
    
    # Check if data disk already mounted
    if mount | grep -q "$MOUNT_POINT"; then
        echo "Data disk already mounted at $MOUNT_POINT"
    else
        # Detect built-in local SSD (inbuilt-lssd storage type)
        if [[ "$STORAGE_TYPE" == "inbuilt-lssd" ]]; then
            echo "=== LSSD Machine Detected - Setting up RAID-0 ==="
            
            # Wait for NVMe devices to appear
            sleep 5
            
            # Find all local NVMe SSDs (exclude boot disk - it has partitions)
            NVME_DEVICES=""
            for dev in /dev/nvme*n1; do
                # Skip if it has partitions (it's the boot disk)
                if ! ls $${dev}p* &>/dev/null 2>&1; then
                    NVME_DEVICES="$NVME_DEVICES $dev"
                fi
            done
            NVME_DEVICES=$(echo $NVME_DEVICES | xargs)  # Trim whitespace
            
            if [ -z "$NVME_DEVICES" ]; then
                echo "ERROR: No local NVMe SSDs found"
                lsblk
                exit 1
            fi
            
            DEVICE_COUNT=$(echo $NVME_DEVICES | wc -w)
            echo "Found $DEVICE_COUNT local NVMe SSDs: $NVME_DEVICES"
            
            # Install mdadm if not present
            if ! command -v mdadm &>/dev/null; then
                apt-get update -qq && apt-get install -y -qq mdadm
            fi
            
            # Check if RAID already exists
            if [ -e /dev/md0 ] && mdadm --detail /dev/md0 &>/dev/null; then
                echo "RAID array /dev/md0 already exists"
                DEVICE="/dev/md0"
            else
                echo "Creating RAID-0 array from $DEVICE_COUNT devices..."
                mdadm --create /dev/md0 --level=0 --raid-devices=$DEVICE_COUNT $NVME_DEVICES --force --run
                DEVICE="/dev/md0"
                
                # Wait for array to be ready
                sleep 2
            fi
            
            # Format if needed (LSSD always needs formatting - data comes via rsync)
            if ! blkid "$DEVICE" &>/dev/null; then
                echo "Formatting $DEVICE with XFS..."
                mkfs.xfs -f "$DEVICE"
            fi
            
            # Mount with noatime for better performance
            mkdir -p "$MOUNT_POINT"
            mount -o noatime,nodiratime "$DEVICE" "$MOUNT_POINT"
            
            echo "RAID-0 array mounted at $MOUNT_POINT with noatime"
            df -h "$MOUNT_POINT"
            
        else
            # Persistent disk (pd-* or hyperdisk-*) - created from snapshot
            DEVICE="/dev/disk/by-id/google-data-disk"
            
            echo "Waiting for device $DEVICE..."
            for i in $(seq 1 30); do
                if [[ -e "$DEVICE" ]]; then
                    echo "Device found!"
                    break
                fi
                echo "  Attempt $i/30..."
                sleep 2
            done
            
            if [[ ! -e "$DEVICE" ]]; then
                echo "ERROR: Device $DEVICE not found after 60 seconds"
                lsblk
                ls -la /dev/disk/by-id/
                exit 1
            fi
            
            # Resolve symlink to actual device
            REAL_DEVICE=$(readlink -f "$DEVICE")
            echo "Resolved device: $DEVICE -> $REAL_DEVICE"
            
            # Check if already formatted (disk from snapshot should already have filesystem)
            if blkid "$DEVICE" &>/dev/null; then
                echo "Disk already has filesystem (created from snapshot)"
            else
                echo "ERROR: Disk has no filesystem - was it created from a snapshot?"
                echo "Disks must be created from golden snapshot, not blank."
                exit 1
            fi
            
            # Create mount point
            mkdir -p "$MOUNT_POINT"
            
            # Get UUID for fstab entry
            UUID=$(blkid -s UUID -o value "$DEVICE")
            echo "Disk UUID: $UUID"
            
            # Add to fstab if not already present (with nofail for resilience, noatime for performance)
            if ! grep -q "$UUID" /etc/fstab; then
                echo "UUID=$UUID $MOUNT_POINT xfs defaults,noatime,nodiratime,nofail 0 2" >> /etc/fstab
            fi
            
            # Mount
            mount "$MOUNT_POINT"
            
            echo "Persistent disk mounted at $MOUNT_POINT"
            df -h "$MOUNT_POINT"
            
            # Verify data exists (from snapshot)
            if [ -d "$MOUNT_POINT/op-reth/db" ]; then
                echo "Database directory found - snapshot data present"
            else
                echo "WARNING: No database found at $MOUNT_POINT/op-reth/db"
                echo "This may indicate the snapshot was not properly restored"
            fi
        fi
    fi
    
    echo "=== Disk Setup Complete ==="
  EOF
}

# -----------------------------------------------------------------------------
# Persistent Disk (only for non-LSSD storage types)
# Created from golden snapshot for fast provisioning
# -----------------------------------------------------------------------------
resource "google_compute_disk" "data" {
  count   = local.create_persistent_disk ? 1 : 0
  name    = "${var.name}-data"
  type    = var.storage_type
  zone    = var.zone
  size    = var.snapshot_disk_size_gb  # Use snapshot disk size, not default
  project = var.project_id

  # Create from golden snapshot (required for fast provisioning)
  snapshot = local.snapshot_self_link

  # Hyperdisk-specific settings (ignored for pd-* types)
  # Note: hyperdisk-extreme only supports IOPS, not throughput
  provisioned_iops       = local.is_hyperdisk ? var.provisioned_iops : null
  provisioned_throughput = local.is_hyperdisk && !local.is_hyperdisk_extreme ? var.provisioned_throughput : null

  labels = var.labels

  lifecycle {
    # SAFETY: Prevent accidental deletion of data disk
    # This disk contains synced blockchain data which takes days to rebuild.
    # To delete, you must first remove this lifecycle rule or remove from state.
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# VM Instance (using google-beta for C3 LSSD machine type support)
# -----------------------------------------------------------------------------
resource "google_compute_instance" "vm" {
  provider = google-beta

  name         = var.name
  machine_type = var.machine_type
  zone         = var.zone
  project      = var.project_id

  # For TDX confidential compute
  dynamic "confidential_instance_config" {
    for_each = var.confidential_compute ? [1] : []
    content {
      confidential_instance_type = "TDX"
    }
  }

  # TDX requires TERMINATE on host maintenance
  # Machines with built-in local SSDs also require TERMINATE (local SSDs don't survive live migration)
  scheduling {
    on_host_maintenance = var.confidential_compute || local.has_builtin_lssd ? "TERMINATE" : "MIGRATE"
    automatic_restart   = true
  }

  boot_disk {
    initialize_params {
      image = data.google_compute_image.vm_image.self_link
      size  = 100  # Boot disk size in GB
      # C4 machines and C3 metal machines require hyperdisk-balanced for boot disk
      type = (
        startswith(var.machine_type, "c4-") ||
        endswith(var.machine_type, "-metal")
      ) ? "hyperdisk-balanced" : "pd-balanced"
    }
  }

  # Attach data disk (only for non-LSSD - created from snapshot)
  dynamic "attached_disk" {
    for_each = local.create_persistent_disk ? [1] : []
    content {
      source      = google_compute_disk.data[0].self_link
      device_name = "data-disk"
      mode        = "READ_WRITE"
    }
  }

  network_interface {
    network = var.network
    access_config {
      # Ephemeral external IP
    }
  }

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = local.startup_script

  labels = merge(var.labels, {
    reth-version = var.reth_version
    storage-type = local.storage_type_label
  })

  # Allow the instance to be replaced if needed
  allow_stopping_for_update = true

  # Ignore scratch_disk changes - machines with built-in local SSDs (inbuilt-lssd)
  # have NVMe drives that appear in Terraform state but aren't defined in config.
  # Without this, Terraform would try to recreate these VMs on every apply.
  lifecycle {
    ignore_changes = [scratch_disk]
  }
}
