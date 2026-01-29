# =============================================================================
# Main Terraform Configuration
# =============================================================================

# =============================================================================
# Enable Required APIs (always runs)
# =============================================================================
module "apis" {
  source     = "./modules/apis"
  project_id = var.project_id
}

# =============================================================================
# Cloud Build Private Pool
# =============================================================================
# Required for Cloud Build to SSH to VMs via internal IP.
# Always created as it's shared infrastructure for all builds.
# =============================================================================
module "cloudbuild_pool" {
  source     = "./modules/cloudbuild-pool"
  project_id = var.project_id
  region     = var.region

  depends_on = [module.apis]
}

# =============================================================================
# L1 Infrastructure (BNE)
# =============================================================================
# Only created when create_l1 = true (for initial L1 setup).
# BNE nodes use public endpoints with API key authentication.
# =============================================================================

# -----------------------------------------------------------------------------
# BNE Module - Blockchain Node Engine (L1 Ethereum Node)
# -----------------------------------------------------------------------------
module "bne" {
  source = "./modules/bne"
  count  = var.create_l1 ? 1 : 0

  project_id = var.project_id
  region     = var.region
  l1_network = local.l1_network
  labels     = local.l1_labels

  depends_on = [module.apis]
}

# -----------------------------------------------------------------------------
# Local - Resolve L1 endpoints
# -----------------------------------------------------------------------------
# When creating L1: extract from BNE module outputs
# When provisioning: use variables passed at deploy time
# -----------------------------------------------------------------------------
locals {
  # L1 endpoints - from BNE module when creating, from variables when provisioning
  l1_rpc_endpoint = var.create_l1 ? (
    length(module.bne) > 0 ? "https://${module.bne[0].json_rpc_endpoint}" : ""
  ) : var.l1_rpc_endpoint

  l1_beacon_endpoint = var.create_l1 ? (
    length(module.bne) > 0 ? "https://${module.bne[0].beacon_endpoint}" : ""
  ) : var.l1_beacon_endpoint

  # API key for BNE access (only used in Ansible inventory)
  l1_api_key = var.l1_api_key
}

# =============================================================================
# Benchmark Infrastructure
# =============================================================================
# Created when create_l1 = false and instances is not empty.
# =============================================================================

# -----------------------------------------------------------------------------
# Shared IAM Module - Single service account for all benchmark VMs
# -----------------------------------------------------------------------------
module "iam" {
  source = "./modules/iam"
  count  = var.create_l1 ? 0 : (length(var.instances) > 0 ? 1 : 0)

  project_id = var.project_id
  gcs_bucket = var.gcs_bucket

  depends_on = [module.apis]
}

# -----------------------------------------------------------------------------
# Benchmark Instances - One VM + disk per instance
# -----------------------------------------------------------------------------
module "benchmark" {
  source   = "./modules/benchmark"
  for_each = var.create_l1 ? {} : var.instances

  # Use the key directly as the VM name (comes from config.toml [[vm]] name)
  name         = each.key
  project_id   = var.project_id
  zone         = var.zone
  machine_type = each.value.machine_type
  storage_type = each.value.storage_type
  disk_size_gb = each.value.disk_size_gb
  reth_version = each.value.reth_version

  # Hyperdisk settings
  provisioned_iops       = each.value.provisioned_iops
  provisioned_throughput = each.value.provisioned_throughput

  # Golden snapshot for fast provisioning (persistent disks only)
  snapshot_name         = var.snapshot_name
  snapshot_disk_size_gb = var.snapshot_disk_size_gb

  service_account_email = module.iam[0].service_account_email
  confidential_compute  = each.value.confidential_compute
  image_family          = var.image_family
  image_project         = var.image_project
  mount_point           = local.mount_point

  labels = {
    project      = "reth-benchmark"
    network      = var.network
    machine-type = replace(each.value.machine_type, "/", "-")
    storage-type = each.value.storage_type != null ? each.value.storage_type : "lssd"
    reth-version = each.value.reth_version
    managed-by   = "terraform"
  }

  depends_on = [module.apis, module.iam]
}

# =============================================================================
# Ansible Inventory Generation
# =============================================================================
# Generate inventory file for Ansible to configure the VMs
# =============================================================================

resource "local_file" "ansible_inventory" {
  count = var.create_l1 ? 0 : (length(var.instances) > 0 ? 1 : 0)

  filename = "${path.module}/../ansible/inventory/hosts.yml"
  content = yamlencode({
    all = {
      hosts = {
        for k, v in module.benchmark : v.vm_name => {
          ansible_host            = v.internal_ip
          ansible_ssh_common_args = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
          reth_version            = v.reth_version
          machine_type            = v.machine_type
          storage_type            = v.storage_type != null ? v.storage_type : "lssd"
          vm_name                 = v.vm_name
          op_node_version         = var.instances[k].op_node_version
          confidential_compute    = v.confidential_compute
          # Performance tuning
          engine_cache_mb = var.instances[k].engine_cache_mb
          engine_workers  = var.instances[k].engine_workers
          # LSSD machines need rsync from temp disk
          is_lssd_machine = v.is_lssd_machine
        }
      }
      vars = {
        l1_rpc_endpoint      = local.l1_rpc_endpoint
        l1_beacon_endpoint   = local.l1_beacon_endpoint
        l1_api_key           = local.l1_api_key != null ? local.l1_api_key : ""
        gcs_bucket           = var.gcs_bucket
        network              = var.network
        mount_point          = local.mount_point
        service_user         = "reth"
        service_group        = "reth"
        tracing_enabled      = var.tracing_enabled
        tracing_sample_ratio = var.tracing_sample_ratio
        tracing_filter       = var.tracing_filter
        # Reth configuration
        reth_batch_size      = var.reth_batch_size
        reth_batch_duration  = var.reth_batch_duration
        db_max_size_bytes    = var.db_max_size_gb * 1024 * 1024 * 1024
        db_growth_step_bytes = var.db_growth_step_mb * 1024 * 1024
      }
    }
  })

  file_permission = "0644"
}

# =============================================================================
# Monitoring Dashboard
# =============================================================================
module "monitoring" {
  source     = "./modules/monitoring"
  count      = var.create_l1 ? 0 : 1
  project_id = var.project_id

  depends_on = [module.apis]
}

# =============================================================================
# Cloud Trace IAM (for OTLP trace ingestion)
# =============================================================================
resource "google_project_iam_member" "benchmark_trace_agent" {
  count   = var.create_l1 ? 0 : (var.tracing_enabled && length(module.iam) > 0 ? 1 : 0)
  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${module.iam[0].service_account_email}"
}
