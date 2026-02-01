#!/usr/bin/env bash
# Build op-node binary (extract from Docker image)
source "$(dirname "$0")/common.sh"

load_config

header "Building op-node"
echo "Version: $OP_NODE_VERSION"
echo ""

submit_build "cloudbuild/builds/op-node.yaml" \
    "_OP_NODE_VERSION=$OP_NODE_VERSION,_GCS_BUCKET=$GCS_BUCKET"
