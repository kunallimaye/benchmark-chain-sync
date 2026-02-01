#!/usr/bin/env bash
# Apply foundation infrastructure (APIs, IAM, Cloud Build Pool)
source "$(dirname "$0")/common.sh"

load_config

header "Applying Foundation Infrastructure"

submit_build "cloudbuild/foundation/apply.yaml"
