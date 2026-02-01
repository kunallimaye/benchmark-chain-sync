#!/usr/bin/env bash
# Build op-reth binary from source
source "$(dirname "$0")/common.sh"

load_config

# Optional commit override from environment
RETH_COMMIT="${RETH_COMMIT:-}"

header "Building op-reth"
echo "Repo:   $RETH_REPO"
echo "Branch: $RETH_BRANCH"
[[ -n "$RETH_COMMIT" ]] && echo "Commit: $RETH_COMMIT"
echo ""

submit_build "cloudbuild/builds/op-reth.yaml" \
    "_RETH_REPO=$RETH_REPO,_RETH_BRANCH=$RETH_BRANCH,_RETH_COMMIT=$RETH_COMMIT,_GCS_BUCKET=$GCS_BUCKET"
