#!/usr/bin/env bash
# Check BNE node sync status and endpoints
source "$(dirname "$0")/common.sh"

load_config

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
