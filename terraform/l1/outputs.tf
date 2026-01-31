# =============================================================================
# L1 Module Outputs
# =============================================================================

output "node_id" {
  description = "The BNE node ID"
  value       = google_blockchain_node_engine_blockchain_nodes.l1.blockchain_node_id
}

output "name" {
  description = "The fully qualified name of the BNE node"
  value       = google_blockchain_node_engine_blockchain_nodes.l1.name
}

# Public endpoint outputs (for FULL nodes with public access)
output "json_rpc_endpoint" {
  description = "Public JSON-RPC API endpoint hostname"
  value       = google_blockchain_node_engine_blockchain_nodes.l1.connection_info[0].endpoint_info[0].json_rpc_api_endpoint
}

output "websockets_endpoint" {
  description = "Public WebSockets API endpoint hostname"
  value       = google_blockchain_node_engine_blockchain_nodes.l1.connection_info[0].endpoint_info[0].websockets_api_endpoint
}

output "beacon_endpoint" {
  description = "Public Beacon API endpoint hostname"
  value       = google_blockchain_node_engine_blockchain_nodes.l1.ethereum_details[0].additional_endpoints[0].beacon_api_endpoint
}
