# =============================================================================
# Blockchain Node Engine (BNE) Module
# =============================================================================
# Creates a BNE Ethereum archive node for L1 access.
# BNE nodes take several days to sync initially.
# =============================================================================

# Enable the BNE API
resource "google_project_service" "bne" {
  project            = var.project_id
  service            = "blockchainnodeengine.googleapis.com"
  disable_on_destroy = false
}

# Create the BNE node
resource "google_blockchain_node_engine_blockchain_nodes" "l1" {
  project            = var.project_id
  location           = var.region
  blockchain_type    = "ETHEREUM"
  blockchain_node_id = "l1-${lower(var.l1_network)}"

  ethereum_details {
    network          = var.l1_network
    node_type        = "FULL"
    consensus_client = "LIGHTHOUSE"
    execution_client = "GETH"
  }

  labels = var.labels

  depends_on = [google_project_service.bne]

  # BNE nodes take a long time to create and sync
  timeouts {
    create = "60m"
    delete = "30m"
  }
}
