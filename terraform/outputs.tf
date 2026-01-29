# =============================================================================
# Terraform Outputs
# =============================================================================

# =============================================================================
# L1 Infrastructure Outputs (when create_l1 = true)
# =============================================================================

output "l1_bne_node_id" {
  description = "BNE node ID"
  value       = var.create_l1 && length(module.bne) > 0 ? module.bne[0].node_id : null
}

output "l1_bne_name" {
  description = "BNE node fully qualified name"
  value       = var.create_l1 && length(module.bne) > 0 ? module.bne[0].name : null
}

output "l1_json_rpc_endpoint" {
  description = "L1 JSON-RPC API endpoint URL (only when create_l1=true)"
  value       = var.create_l1 && length(module.bne) > 0 ? "https://${module.bne[0].json_rpc_endpoint}" : null
}

output "l1_beacon_api_endpoint" {
  description = "L1 Beacon API endpoint URL (only when create_l1=true)"
  value       = var.create_l1 && length(module.bne) > 0 ? "https://${module.bne[0].beacon_endpoint}" : null
}

output "l1_websockets_endpoint" {
  description = "L1 WebSockets API endpoint URL (only when create_l1=true)"
  value       = var.create_l1 && length(module.bne) > 0 ? "wss://${module.bne[0].websockets_endpoint}" : null
}

# =============================================================================
# Benchmark Infrastructure Outputs (when create_l1 = false)
# =============================================================================

output "instances" {
  description = "Map of all benchmark instances with their details"
  value = {
    for k, v in module.benchmark : k => {
      name                 = v.vm_name
      external_ip          = v.external_ip
      internal_ip          = v.internal_ip
      zone                 = v.zone
      reth_version         = v.reth_version
      machine_type         = v.machine_type
      storage_type         = v.storage_type
      confidential_compute = v.confidential_compute
    }
  }
}

output "service_account_email" {
  description = "Email of the shared service account"
  value       = length(module.iam) > 0 ? module.iam[0].service_account_email : null
}

output "inventory_path" {
  description = "Path to the generated Ansible inventory file"
  value       = length(local_file.ansible_inventory) > 0 ? local_file.ansible_inventory[0].filename : null
}

# =============================================================================
# Common Outputs
# =============================================================================

output "project_id" {
  description = "GCP project ID"
  value       = var.project_id
}

output "zone" {
  description = "GCP zone"
  value       = var.zone
}

output "gcs_bucket" {
  description = "GCS bucket for artifacts"
  value       = var.gcs_bucket
}

output "network" {
  description = "Base network (base-mainnet or base-sepolia)"
  value       = var.network
}

output "cloudbuild_pool_name" {
  description = "Cloud Build private pool resource name"
  value       = module.cloudbuild_pool.pool_name
}

output "dashboard_url" {
  description = "Cloud Monitoring dashboard URL (overview)"
  value       = var.create_l1 ? null : (length(module.monitoring) > 0 ? module.monitoring[0].dashboard_url : null)
}

output "dashboard_v1_url" {
  description = "Cloud Monitoring dashboard URL (v1 - detailed stage analysis)"
  value       = var.create_l1 ? null : (length(module.monitoring) > 0 ? module.monitoring[0].dashboard_v1_url : null)
}
