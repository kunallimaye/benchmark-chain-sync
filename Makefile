# =============================================================================
# op-reth Base Benchmark - Makefile
# =============================================================================
# Thin wrapper around scripts/ - all logic lives in shell scripts.
# See: make help for usage details.
#
# IMPORTANT: Keep this Makefile minimal. All logic should be in scripts/.
# =============================================================================

-include .env
export L1_API_KEY

# Variables (passed to scripts via flags)
VM ?=
SNAPSHOT ?=
TYPE ?=
WAIT ?=
FORCE ?=
RETH_COMMIT ?=

# Build flag strings for scripts
_VM_FLAG = $(if $(VM),--vm=$(VM))
_WAIT_FLAG = $(if $(WAIT),--wait)
_FORCE_FLAG = $(if $(FORCE),--force)
_SNAPSHOT_FLAG = $(if $(SNAPSHOT),--snapshot=$(SNAPSHOT))
_COMMIT_FLAG = $(if $(RETH_COMMIT),--commit=$(RETH_COMMIT))

.PHONY: help \
        l1-create l1-destroy l1-status create-l1 destroy-l1 status-l1 \
        build-reth build-op-node build-status \
        snapshot-create snapshot-delete snapshot-list create-snapshot delete-snapshot list-snapshots \
        provision provision-plan configure configure-plan cleanup benchmark \
        status status-vm sync-status list-vms list-instances configure-status benchmark-status \
        apply-foundation apply-monitoring \
        validate-config validate-terraform

# -----------------------------------------------------------------------------
# L1 Infrastructure
# -----------------------------------------------------------------------------
l1-create:       ; @./scripts/l1.sh create
l1-destroy:      ; @./scripts/l1.sh destroy
l1-status:       ; @./scripts/l1.sh status

# Aliases for backwards compatibility
create-l1: l1-create
destroy-l1: l1-destroy
status-l1: l1-status

# -----------------------------------------------------------------------------
# Build Binaries
# -----------------------------------------------------------------------------
build-reth:      ; @./scripts/build.sh reth $(_COMMIT_FLAG)
build-op-node:   ; @./scripts/build.sh op-node
build-status:    ; @./scripts/build.sh status $(TYPE)

# -----------------------------------------------------------------------------
# Snapshot Management
# -----------------------------------------------------------------------------
snapshot-create: ; @./scripts/snapshot.sh create $(_VM_FLAG)
snapshot-delete: ; @./scripts/snapshot.sh delete $(_SNAPSHOT_FLAG)
snapshot-list:   ; @./scripts/snapshot.sh list

# Aliases for backwards compatibility
create-snapshot: snapshot-create
delete-snapshot: snapshot-delete
list-snapshots: snapshot-list

# -----------------------------------------------------------------------------
# VM Management
# -----------------------------------------------------------------------------
provision:       ; @./scripts/vm.sh provision $(_VM_FLAG) $(_WAIT_FLAG) $(_FORCE_FLAG)
provision-plan:  ; @./scripts/vm.sh provision $(_VM_FLAG) --plan
configure:       ; @./scripts/vm.sh configure $(_VM_FLAG) $(_WAIT_FLAG) $(_FORCE_FLAG)
configure-plan:  ; @./scripts/vm.sh configure $(_VM_FLAG) --plan
cleanup:         ; @./scripts/vm.sh cleanup $(_VM_FLAG)
benchmark:       ; @./scripts/vm.sh benchmark $(_VM_FLAG)

# -----------------------------------------------------------------------------
# Status & Monitoring
# -----------------------------------------------------------------------------
status:          ; @./scripts/status.sh all
status-vm:       ; @./scripts/status.sh vm $(_VM_FLAG)
sync-status:     ; @./scripts/status.sh sync
list-vms:        ; @./scripts/status.sh vms
list-instances:  ; @./scripts/status.sh instances

# Aliases for backwards compatibility
configure-status: status-vm
benchmark-status: ; @./scripts/build.sh status benchmark

# -----------------------------------------------------------------------------
# Apply Infrastructure
# -----------------------------------------------------------------------------
apply-foundation:  ; @./scripts/apply.sh foundation
apply-monitoring:  ; @./scripts/apply.sh monitoring

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------
validate-config:   ; @./scripts/validate.sh config
validate-terraform: ; @./scripts/validate.sh terraform

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------
help:            ; @./scripts/help.sh
