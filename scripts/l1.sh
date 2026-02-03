#!/usr/bin/env bash
# =============================================================================
# L1 (BNE) Management
# =============================================================================
# Usage: l1.sh {create|destroy|status}
# =============================================================================
source "$(dirname "$0")/common.sh"

ACTION="${1:-}"
shift || true

show_usage() {
    cat << 'EOF'
Usage: l1.sh {create|destroy|status}

Commands:
  create    Create L1 BNE node (takes days to sync!)
  destroy   Destroy L1 infrastructure (WARNING: re-sync takes days!)
  status    Check BNE node sync status and endpoints
EOF
    exit 1
}

[[ -z "$ACTION" ]] && show_usage

load_config

case "$ACTION" in
    create)
        header "Creating L1 Infrastructure (BNE)"
        echo "Network: $CHAIN_NETWORK -> L1: $L1_NETWORK"
        warn "BNE nodes take several days to sync!"
        echo ""
        submit_build "cloudbuild/l1/create.yaml"
        ;;
        
    destroy)
        header "Destroying L1 Infrastructure"
        warn "Re-syncing BNE takes several days!"
        confirm "Are you sure?" || exit 0
        submit_build "cloudbuild/l1/destroy.yaml"
        ;;
        
    status)
        header "L1 BNE Node Status"
        gcloud alpha blockchain-node-engine nodes describe "l1-$L1_NETWORK" \
            --location="$REGION" \
            --project="$PROJECT_ID" \
            --format="table(name,state,ethereumDetails.network,ethereumDetails.nodeType)" \
            2>/dev/null || echo "BNE node not found or CLI not available"
        
        echo ""
        header "Public Endpoints"
        
        JSON_RPC=$(gcloud alpha blockchain-node-engine nodes describe "l1-$L1_NETWORK" \
            --location="$REGION" \
            --project="$PROJECT_ID" \
            --format='value(connectionInfo.endpointInfo.jsonRpcApiEndpoint)' 2>/dev/null || echo 'pending')
        
        BEACON=$(gcloud alpha blockchain-node-engine nodes describe "l1-$L1_NETWORK" \
            --location="$REGION" \
            --project="$PROJECT_ID" \
            --format='value(ethereumDetails.additionalEndpoints.beaconApiEndpoint)' 2>/dev/null || echo 'pending')
        
        echo "JSON-RPC: $JSON_RPC"
        echo "Beacon:   $BEACON"
        ;;
        
    *)
        error "Unknown action: $ACTION"
        show_usage
        ;;
esac
