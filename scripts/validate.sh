#!/usr/bin/env bash
# =============================================================================
# Validation Commands
# =============================================================================
# Usage: validate.sh {config|terraform}
# =============================================================================
source "$(dirname "$0")/common.sh"

ACTION="${1:-config}"

show_usage() {
    cat << 'EOF'
Usage: validate.sh {config|terraform}

Commands:
  config      Validate config.toml syntax
  terraform   Validate Terraform configuration
EOF
    exit 1
}

case "$ACTION" in
    config)
        header "Validating config.toml"
        if python3 "$SCRIPTS_DIR/config.py" >/dev/null 2>&1; then
            success "config.toml is valid"
        else
            die "config.toml has syntax errors"
        fi
        ;;
        
    terraform)
        header "Validating Terraform"
        cd "$PROJECT_ROOT/terraform" && terraform init -backend=false && terraform validate
        ;;
        
    *)
        error "Unknown action: $ACTION"
        show_usage
        ;;
esac
