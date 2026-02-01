#!/usr/bin/env bash
# Destroy L1 BNE node (WARNING: re-sync takes days!)
source "$(dirname "$0")/common.sh"

load_config

header "Destroying L1 Infrastructure"
warn "Re-syncing BNE takes several days!"

confirm "Are you sure?" || exit 0

submit_build "cloudbuild/l1/destroy.yaml"
