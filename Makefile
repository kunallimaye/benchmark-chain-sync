# =============================================================================
# op-reth Base Benchmark - Makefile
# =============================================================================
# Thin wrapper around scripts/ - all logic lives in shell scripts.
# See: ./scripts/help.sh for usage details.
#
# IMPORTANT: Keep this Makefile minimal. All logic should be in scripts/.
# =============================================================================

-include .env
export L1_API_KEY

# Variables (passed to scripts)
VM ?=
SNAPSHOT ?=
TYPE ?=
WAIT ?=
RETH_COMMIT ?=

.PHONY: help create-l1 destroy-l1 status-l1 build-reth build-op-node \
        create-snapshot list-snapshots delete-snapshot \
        provision provision-plan configure benchmark cleanup \
        status configure-status build-status benchmark-status sync-status \
        list-vms list-instances apply-foundation apply-monitoring \
        validate-config validate-terraform

# -----------------------------------------------------------------------------
# L1 Infrastructure
# -----------------------------------------------------------------------------
create-l1:        ; @./scripts/l1-create.sh
destroy-l1:       ; @./scripts/l1-destroy.sh
status-l1:        ; @./scripts/l1-status.sh

# -----------------------------------------------------------------------------
# Build Binaries
# -----------------------------------------------------------------------------
build-reth:       ; @RETH_COMMIT="$(RETH_COMMIT)" ./scripts/build-reth.sh
build-op-node:    ; @./scripts/build-op-node.sh

# -----------------------------------------------------------------------------
# Snapshot Management
# -----------------------------------------------------------------------------
create-snapshot:  ; @./scripts/snapshot-create.sh "$(VM)"
list-snapshots:   ; @./scripts/snapshot-list.sh
delete-snapshot:  ; @./scripts/snapshot-delete.sh "$(SNAPSHOT)"

# -----------------------------------------------------------------------------
# Benchmark Infrastructure
# -----------------------------------------------------------------------------
provision:        ; @./scripts/provision.sh "$(VM)" "$(WAIT)"
provision-plan:   ; @./scripts/provision.sh "$(VM)" "" --plan
configure:        ; @./scripts/configure.sh "$(VM)" "$(WAIT)"
benchmark:        ; @./scripts/benchmark.sh "$(VM)"
cleanup:          ; @./scripts/cleanup.sh "$(VM)"

# -----------------------------------------------------------------------------
# Status & Monitoring
# -----------------------------------------------------------------------------
status:           ; @./scripts/status.sh
configure-status: ; @./scripts/status-vm.sh "$(VM)"
build-status:     ; @./scripts/status-build.sh "$(TYPE)"
benchmark-status: ; @./scripts/status-build.sh benchmark
sync-status:      ; @./scripts/sync-status.sh
list-vms:         ; @./scripts/list-vms.sh
list-instances:   ; @./scripts/list-instances.sh

# -----------------------------------------------------------------------------
# Foundation
# -----------------------------------------------------------------------------
apply-foundation: ; @./scripts/apply-foundation.sh
apply-monitoring: ; @./scripts/apply-monitoring.sh

# -----------------------------------------------------------------------------
# Utilities
# -----------------------------------------------------------------------------
validate-config:  ; @./scripts/validate-config.sh
validate-terraform: ; @cd terraform && terraform init -backend=false && terraform validate
help:             ; @./scripts/help.sh
