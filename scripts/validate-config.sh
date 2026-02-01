#!/usr/bin/env bash
# Validate config.toml syntax
source "$(dirname "$0")/common.sh"

header "Validating config.toml"

if python3 "$SCRIPTS_DIR/config.py" >/dev/null 2>&1; then
    success "config.toml is valid"
else
    die "config.toml has syntax errors"
fi
