#!/usr/bin/env bash
# Create L1 BNE node (takes days to sync!)
source "$(dirname "$0")/common.sh"

load_config

header "Creating L1 Infrastructure (BNE)"
echo "Network: $CHAIN_NETWORK -> L1: $L1_NETWORK"
warn "BNE nodes take several days to sync!"
echo ""

submit_build "cloudbuild/l1/create.yaml"
