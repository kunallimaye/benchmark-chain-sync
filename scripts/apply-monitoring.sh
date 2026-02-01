#!/usr/bin/env bash
# Apply monitoring infrastructure (dashboards, log metrics)
source "$(dirname "$0")/common.sh"

load_config

header "Applying Monitoring Infrastructure"

submit_build "cloudbuild/monitoring/apply.yaml"
