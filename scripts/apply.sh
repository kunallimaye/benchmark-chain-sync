#!/usr/bin/env bash
# =============================================================================
# Apply Infrastructure Modules
# =============================================================================
# Usage: apply.sh {foundation|monitoring}
# =============================================================================
source "$(dirname "$0")/common.sh"

ACTION="${1:-}"

show_usage() {
    cat << 'EOF'
Usage: apply.sh {foundation|monitoring}

Commands:
  foundation    Apply foundation infrastructure (APIs, IAM, Cloud Build Pool)
  monitoring    Apply monitoring infrastructure (dashboards, log metrics)
EOF
    exit 1
}

[[ -z "$ACTION" ]] && show_usage

load_config

case "$ACTION" in
    foundation)
        header "Applying Foundation Infrastructure"
        submit_build "cloudbuild/foundation/apply.yaml"
        ;;
        
    monitoring)
        header "Applying Monitoring Infrastructure"
        submit_build "cloudbuild/monitoring/apply.yaml"
        ;;
        
    *)
        error "Unknown action: $ACTION"
        show_usage
        ;;
esac
