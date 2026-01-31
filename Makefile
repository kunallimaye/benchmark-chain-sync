# =============================================================================
# op-reth Base Benchmark - Makefile
# =============================================================================
# All Cloud Build jobs are triggered manually via this Makefile.
# Configuration is read from config.toml and .env files.
#
# Workflow:
#   1. make create-l1                    # Create L1 BNE node (one-time)
#   2. make build-reth                   # Build op-reth binary
#   3. make build-op-node                # Build op-node binary
#   4. make create-snapshot VM=<name>    # Create golden snapshot from synced VM
#   5. Edit config.toml with VM configs  # Define VMs + snapshot name
#   6. make provision                    # Create all VMs (or VM=name for one)
#   7. make configure                    # Configure all VMs (or VM=name)
#   8. make benchmark VM=name            # Run benchmark on specific VM
#   9. make cleanup                      # Destroy all VMs (or VM=name)
# =============================================================================

.PHONY: build-reth build-op-node provision provision-plan configure benchmark \
        cleanup list-instances \
        create-l1 destroy-l1 status-l1 \
        create-snapshot list-snapshots delete-snapshot \
        status validate-terraform help \
        build-status configure-status benchmark-status \
        apply-foundation apply-monitoring

# -----------------------------------------------------------------------------
# Load environment variables from .env if it exists
# -----------------------------------------------------------------------------
-include .env
export L1_API_KEY

# -----------------------------------------------------------------------------
# Configuration from config.toml (parsed via shell)
# These are used for targets that don't go through Cloud Build
# Note: Use := for immediate evaluation to avoid repeated shell calls
# -----------------------------------------------------------------------------
PROJECT_ID := $(shell grep -A1 '^\[project\]' config.toml | grep 'project_id' | cut -d'"' -f2)
REGION := $(shell grep -A2 '^\[project\]' config.toml | grep 'region' | cut -d'"' -f2)
ZONE := $(shell grep -A3 '^\[project\]' config.toml | grep 'zone' | cut -d'"' -f2)
NETWORK := $(shell grep -A4 '^\[project\]' config.toml | grep 'network' | cut -d'"' -f2)
GCS_BUCKET := $(shell grep -A5 '^\[project\]' config.toml | grep 'gcs_bucket' | cut -d'"' -f2)

# Derived L1 network (mainnet for base-mainnet, holesky for base-sepolia)
L1_NETWORK := $(if $(filter base-mainnet,$(NETWORK)),mainnet,holesky)

# Build configuration (can be overridden via command line)
RETH_REPO := $(shell grep -A1 '^\[build\]' config.toml | grep 'reth_repo' | cut -d'"' -f2)
RETH_BRANCH := $(shell grep -A2 '^\[build\]' config.toml | grep 'reth_branch' | cut -d'"' -f2)
RETH_COMMIT ?=
OP_NODE_VERSION := $(shell grep -A3 '^\[build\]' config.toml | grep 'op_node_version' | cut -d'"' -f2)

# Snapshot configuration
SNAPSHOT_NAME := $(shell grep -A1 '^\[snapshot\]' config.toml | grep 'name' | cut -d'"' -f2)

# VM filter (optional - if set, only operate on this VM)
VM ?=

# Snapshot name for delete-snapshot target
SNAPSHOT ?=

# =============================================================================
# Foundation Infrastructure (APIs, IAM, Cloud Build Pool)
# =============================================================================

apply-foundation: ## Apply foundation infrastructure (APIs, IAM, Cloud Build Pool)
	@echo "=== Applying Foundation Infrastructure ==="
	gcloud builds submit . \
		--config=cloudbuild/foundation/apply.yaml \
		--project=$(PROJECT_ID)

apply-monitoring: ## Apply monitoring infrastructure (dashboards, log metrics)
	@echo "=== Applying Monitoring Infrastructure ==="
	gcloud builds submit . \
		--config=cloudbuild/monitoring/apply.yaml \
		--project=$(PROJECT_ID)

# =============================================================================
# L1 Infrastructure (BNE)
# =============================================================================

create-l1: ## Create L1 BNE node (takes days to sync!)
	@echo "=== Creating L1 Infrastructure (BNE) ==="
	@echo "Network: $(NETWORK) -> L1: $(L1_NETWORK)"
	@echo "WARNING: BNE nodes take several days to sync!"
	@echo ""
	gcloud builds submit . \
		--config=cloudbuild/l1/create.yaml \
		--project=$(PROJECT_ID)

destroy-l1: ## Destroy L1 infrastructure (WARNING: re-sync takes days!)
	@echo "=== Destroying L1 Infrastructure ==="
	@echo "WARNING: Re-syncing BNE takes several days!"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	gcloud builds submit . \
		--config=cloudbuild/l1/destroy.yaml \
		--project=$(PROJECT_ID)

status-l1: ## Check BNE node sync status and endpoints
	@echo "=== L1 BNE Node Status ==="
	@gcloud alpha blockchain-node-engine nodes describe "l1-$(L1_NETWORK)" \
		--location=$(REGION) \
		--project=$(PROJECT_ID) \
		--format="table(name,state,ethereumDetails.network,ethereumDetails.nodeType)" \
		2>/dev/null || echo "BNE node not found or CLI not available"
	@echo ""
	@echo "=== Public Endpoints ==="
	@echo "JSON-RPC: $$(gcloud alpha blockchain-node-engine nodes describe l1-$(L1_NETWORK) \
		--location=$(REGION) --project=$(PROJECT_ID) \
		--format='value(connectionInfo.endpointInfo.jsonRpcApiEndpoint)' 2>/dev/null || echo 'pending')"
	@echo "Beacon:   $$(gcloud alpha blockchain-node-engine nodes describe l1-$(L1_NETWORK) \
		--location=$(REGION) --project=$(PROJECT_ID) \
		--format='value(ethereumDetails.additionalEndpoints.beaconApiEndpoint)' 2>/dev/null || echo 'pending')"

# =============================================================================
# Build Binaries
# =============================================================================

build-reth: ## Build op-reth binary (uses config.toml [build] section)
	@echo "=== Building op-reth ==="
	@echo "Repo:   $(RETH_REPO)"
	@echo "Branch: $(RETH_BRANCH)"
	@[ -n "$(RETH_COMMIT)" ] && echo "Commit: $(RETH_COMMIT)" || true
	@echo ""
	gcloud builds submit . \
		--config=cloudbuild/builds/op-reth.yaml \
		--project=$(PROJECT_ID) \
		--substitutions=_RETH_REPO=$(RETH_REPO),_RETH_BRANCH=$(RETH_BRANCH),_RETH_COMMIT=$(RETH_COMMIT),_GCS_BUCKET=$(GCS_BUCKET)

build-op-node: ## Build op-node binary (extracts from Docker image)
	@echo "=== Building op-node ==="
	@echo "Version: $(OP_NODE_VERSION)"
	@echo ""
	gcloud builds submit . \
		--config=cloudbuild/builds/op-node.yaml \
		--project=$(PROJECT_ID) \
		--substitutions=_OP_NODE_VERSION=$(OP_NODE_VERSION),_GCS_BUCKET=$(GCS_BUCKET)

# =============================================================================
# Golden Snapshot Management
# =============================================================================

create-snapshot: ## Create golden snapshot from a running VM (requires VM=name)
	@if [ -z "$(VM)" ]; then \
		echo "ERROR: VM is required"; \
		echo "Usage: make create-snapshot VM=<name>"; \
		echo ""; \
		echo "This will:"; \
		echo "  1. Stop op-reth on the VM (briefly)"; \
		echo "  2. Create a snapshot of the data disk"; \
		echo "  3. Restart op-reth"; \
		echo ""; \
		echo "Available VMs:"; \
		gcloud compute instances list --project=$(PROJECT_ID) --filter="name~op-reth" --format="value(name)" | sed 's/^/  /'; \
		exit 1; \
	fi
	@echo "=== Creating Golden Snapshot from $(VM) ==="
	@DISK_NAME="$(VM)-data"; \
	SNAPSHOT_NAME="op-reth-golden-$$(date +%Y-%m-%d-%H-%M)"; \
	echo "Source disk: $$DISK_NAME"; \
	echo "Snapshot name: $$SNAPSHOT_NAME"; \
	echo ""; \
	read -p "This will briefly stop op-reth. Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1; \
	echo ""; \
	echo "Stopping op-reth..."; \
	gcloud compute ssh $(VM) --zone=$(ZONE) --project=$(PROJECT_ID) \
		--command="sudo systemctl stop op-reth op-node" 2>/dev/null || true; \
	echo "Creating snapshot..."; \
	gcloud compute snapshots create $$SNAPSHOT_NAME \
		--source-disk=$$DISK_NAME \
		--source-disk-zone=$(ZONE) \
		--project=$(PROJECT_ID) \
		--description="Golden snapshot from $(VM) at $$(date -Iseconds)"; \
	echo "Restarting op-reth..."; \
	gcloud compute ssh $(VM) --zone=$(ZONE) --project=$(PROJECT_ID) \
		--command="sudo systemctl start op-reth op-node" 2>/dev/null || true; \
	echo ""; \
	echo "Snapshot created: $$SNAPSHOT_NAME"; \
	echo ""; \
	echo "Update config.toml [snapshot] section:"; \
	echo "  name = \"$$SNAPSHOT_NAME\""

list-snapshots: ## List golden snapshots
	@echo "=== Golden Snapshots ==="
	@gcloud compute snapshots list \
		--project=$(PROJECT_ID) \
		--filter="name~op-reth-golden" \
		--format="table(name,status,diskSizeGb,creationTimestamp.date('%Y-%m-%d %H:%M'),description)" \
		2>/dev/null || echo "No snapshots found"
	@echo ""
	@echo "Current config.toml snapshot: $(SNAPSHOT_NAME)"

delete-snapshot: ## Delete a golden snapshot (requires SNAPSHOT=name)
	@if [ -z "$(SNAPSHOT)" ]; then \
		echo "ERROR: SNAPSHOT is required"; \
		echo "Usage: make delete-snapshot SNAPSHOT=<name>"; \
		echo ""; \
		echo "Available snapshots:"; \
		gcloud compute snapshots list --project=$(PROJECT_ID) --filter="name~op-reth-golden" --format="value(name)" | sed 's/^/  /'; \
		exit 1; \
	fi
	@echo "=== Deleting Snapshot: $(SNAPSHOT) ==="
	@if [ "$(SNAPSHOT)" = "$(SNAPSHOT_NAME)" ]; then \
		echo "WARNING: This is the snapshot configured in config.toml!"; \
		echo "VMs will fail to provision without a valid snapshot."; \
		echo ""; \
	fi
	@read -p "Are you sure you want to delete $(SNAPSHOT)? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	gcloud compute snapshots delete $(SNAPSHOT) \
		--project=$(PROJECT_ID) \
		--quiet
	@echo "Snapshot deleted: $(SNAPSHOT)"

# =============================================================================
# Provision Infrastructure (Terraform only)
# =============================================================================

provision: ## Create VMs from config.toml (all VMs, or VM=name for specific)
	@echo "=== Provisioning Infrastructure ==="
	@if [ -n "$(VM)" ]; then \
		echo "VM Filter: $(VM)"; \
	else \
		echo "VMs: all from config.toml"; \
	fi
	@echo ""
	gcloud builds submit . \
		--config=cloudbuild/benchmark/provision.yaml \
		--project=$(PROJECT_ID) \
		--substitutions=_GCS_BUCKET=$(GCS_BUCKET),_VM=$(VM) \
		--async 

provision-plan: ## Dry-run provision (terraform plan, no apply)
	@echo "=== Provisioning Plan (dry-run) ==="
	@if [ -n "$(VM)" ]; then \
		echo "VM Filter: $(VM)"; \
	else \
		echo "VMs: all from config.toml"; \
	fi
	@echo ""
	gcloud builds submit . \
		--config=cloudbuild/benchmark/provision.yaml \
		--project=$(PROJECT_ID) \
		--substitutions=_GCS_BUCKET=$(GCS_BUCKET),_VM=$(VM),_PLAN_ONLY=true

# =============================================================================
# Configure Infrastructure (Ansible only)
# =============================================================================

configure: ## Configure VMs with Ansible (all VMs, or VM=name for specific)
	@echo "=== Configuring VMs ==="
	@if [ -n "$(VM)" ]; then \
		echo "VM: $(VM)"; \
	else \
		echo "VMs: all"; \
	fi
	gcloud builds submit . \
		--config=cloudbuild/benchmark/configure.yaml \
		--project=$(PROJECT_ID) \
		--region=$(REGION) \
		--substitutions=_VM=$(VM),_GCS_BUCKET=$(GCS_BUCKET) \
		--async 

# =============================================================================
# Build Status Monitoring
# =============================================================================

build-status: ## Show status of most recent build (TYPE=configure|provision|benchmark|build|cleanup|download)
	@if [ -z "$(TYPE)" ]; then \
		echo "Usage: make build-status TYPE=<type>"; \
		echo ""; \
		echo "Types: configure, provision, benchmark, build, cleanup, create-l1, destroy-l1, download, create-download-disk"; \
		exit 1; \
	fi
	@echo "=== $(TYPE) Build Status ==="
	@case "$(TYPE)" in \
		configure|benchmark) REGION_FLAG="--region=$(REGION)" ;; \
		*) REGION_FLAG="" ;; \
	esac; \
	BUILD_ID=$$(gcloud builds list \
		--project=$(PROJECT_ID) \
		$$REGION_FLAG \
		--filter="tags='$(TYPE)'" \
		--format="value(id)" \
		--limit=1 2>/dev/null); \
	if [ -z "$$BUILD_ID" ]; then \
		echo "No $(TYPE) builds found"; \
		exit 0; \
	fi; \
	echo "Build ID: $$BUILD_ID"; \
	gcloud builds describe $$BUILD_ID \
		--project=$(PROJECT_ID) \
		$$REGION_FLAG \
		--format="table(status,createTime,finishTime)"; \
	echo ""; \
	STATUS=$$(gcloud builds describe $$BUILD_ID --project=$(PROJECT_ID) $$REGION_FLAG --format="value(status)"); \
	if [ "$$STATUS" = "WORKING" ]; then \
		echo "Build is running. Stream logs with:"; \
		echo "  gcloud builds log $$BUILD_ID --project=$(PROJECT_ID) $$REGION_FLAG --stream"; \
	else \
		echo "View logs with:"; \
		echo "  gcloud builds log $$BUILD_ID --project=$(PROJECT_ID) $$REGION_FLAG"; \
	fi

configure-status: ## Show configure/sync status for a VM (requires VM=name)
	@if [ -z "$(VM)" ]; then \
		echo "Usage: make configure-status VM=<name>"; \
		echo ""; \
		echo "Available VMs:"; \
		python3 -c "import tomllib; c=tomllib.load(open('config.toml','rb')); [print(f'  {v.get(\"name\")}') for v in c.get('vm',[])]" || echo "  (none)"; \
		exit 1; \
	fi
	@echo "=== Status for $(VM) ==="
	@gcloud compute ssh $(VM) \
		--zone=$(ZONE) \
		--project=$(PROJECT_ID) \
		--ssh-flag="-o Hostname=nic0.$(VM).$(ZONE).c.$(PROJECT_ID).internal.gcpnode.com" \
		--command='\
		echo ""; \
		echo "=== Services ==="; \
		systemctl is-active op-reth.service 2>/dev/null && echo "op-reth: RUNNING" || echo "op-reth: not running"; \
		systemctl is-active op-node.service 2>/dev/null && echo "op-node: RUNNING" || echo "op-node: not running"; \
		echo ""; \
		echo "=== Data Directory ==="; \
		if [ -f /mnt/data/op-reth/db/mdbx.dat ]; then \
			echo "Database exists"; \
			du -sh /mnt/data/op-reth/db 2>/dev/null || true; \
		else \
			echo "Database not found"; \
		fi; \
		echo ""; \
		echo "=== Disk Usage ==="; \
		df -h /mnt/data 2>/dev/null || echo "Data disk not mounted"; \
		echo ""; \
		echo "=== Recent Logs (op-reth) ==="; \
		journalctl -u op-reth.service -n 10 --no-pager 2>/dev/null || echo "No logs available"; \
	' 2>/dev/null || echo "ERROR: Could not SSH to $(VM). VM may not exist or SSH may not be ready."

benchmark-status: ## Show status of most recent benchmark build
	@$(MAKE) build-status TYPE=benchmark

# =============================================================================
# Run Benchmark
# =============================================================================

benchmark: ## Run benchmark on VM (requires VM=name)
	@if [ -z "$(VM)" ]; then \
		echo "ERROR: VM is required"; \
		echo "Usage: make benchmark VM=op-reth-baseline"; \
		echo ""; \
		echo "Available VMs:"; \
		python3 -c "import tomllib; c=tomllib.load(open('config.toml','rb')); [print(f'  {v.get(\"name\")}') for v in c.get('vm',[])]" || echo "  (none)"; \
		exit 1; \
	fi
	@echo "=== Running benchmark on $(VM) ==="
	gcloud builds submit . \
		--config=cloudbuild/benchmark/run.yaml \
		--project=$(PROJECT_ID) \
		--region=$(REGION) \
		--substitutions=_VM=$(VM),_GCS_BUCKET=$(GCS_BUCKET)

# =============================================================================
# Cleanup
# =============================================================================

cleanup: ## Destroy VMs (all VMs, or VM=name for specific)
	@echo "=== Destroying VMs ==="
	@if [ -n "$(VM)" ]; then \
		echo "VM: $(VM)"; \
	else \
		echo "VMs: all"; \
		read -p "Are you sure you want to destroy ALL VMs? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1; \
	fi
	gcloud builds submit . \
		--config=cloudbuild/benchmark/cleanup.yaml \
		--project=$(PROJECT_ID) \
		--substitutions=_VM=$(VM),_GCS_BUCKET=$(GCS_BUCKET)

# =============================================================================
# Status and Utilities
# =============================================================================

list-vms: ## List VMs defined in config.toml
	@echo "=== VMs in config.toml ==="
	@python3 -c "import tomllib; c=tomllib.load(open('config.toml','rb')); d=c.get('defaults',{}).get('vm',{}); \
		[print(f\"  {v.get('name')}: {v.get('machine_type',d.get('machine_type','?'))} / {'lssd' if v.get('machine_type',d.get('machine_type','')).endswith('-lssd') else v.get('storage_type',d.get('storage_type','?'))} / TDX={v.get('confidential_compute',d.get('confidential_compute',True))}\") for v in c.get('vm',[])]" \
		|| echo "  (none)"

list-instances: ## List active instances in GCS state
	@echo "=== Active Instances ==="
	@gsutil cat "gs://$(GCS_BUCKET)/terraform/instances.json" 2>/dev/null | \
		jq -r 'to_entries[] | "  \(.key): \(.value.machine_type) / \(.value.storage_type) / TDX=\(.value.confidential_compute)"' || echo "  (none)"

status: ## Show current build artifacts and infrastructure
	@echo "=== Build Artifacts ==="
	@gsutil ls -l "gs://$(GCS_BUCKET)/builds/op-reth-*" 2>/dev/null | grep -v '.json$$' | head -20 || echo "  No builds found"
	@echo ""
	@echo "=== Golden Snapshot ==="
	@if [ -n "$(SNAPSHOT_NAME)" ]; then \
		gcloud compute snapshots describe $(SNAPSHOT_NAME) \
			--project=$(PROJECT_ID) \
			--format="table(name,status,diskSizeGb,storageBytes.yesno(yes='size: ',no=''):label='')" \
			2>/dev/null || echo "  $(SNAPSHOT_NAME) (not found)"; \
	else \
		echo "  Not configured in config.toml"; \
	fi
	@echo ""
	@echo "=== VMs in config.toml ==="
	@python3 -c "import tomllib; c=tomllib.load(open('config.toml','rb')); [print(f\"  {v.get('name')}\") for v in c.get('vm',[])]" || echo "  (none)"
	@echo ""
	@echo "=== Active Instances (Terraform state) ==="
	@gsutil cat "gs://$(GCS_BUCKET)/terraform/instances.json" 2>/dev/null | jq -r 'keys[]' | sed 's/^/  /' || echo "  (none)"
	@echo ""
	@echo "=== L1 BNE Node ==="
	@gcloud alpha blockchain-node-engine nodes describe "l1-$(L1_NETWORK)" \
		--location=$(REGION) \
		--project=$(PROJECT_ID) \
		--format="value(state)" \
		2>/dev/null || echo "  Not found"

validate-terraform: ## Validate Terraform configuration
	cd terraform && terraform init -backend=false && terraform validate

validate-config: ## Validate config.toml syntax
	@echo "=== Validating config.toml ==="
	@python3 -c "import tomllib; tomllib.load(open('config.toml', 'rb')); print('config.toml is valid')"

# =============================================================================
# Help
# =============================================================================

help: ## Show this help
	@echo "op-reth Base Benchmark"
	@echo ""
	@echo "Usage: make [target] [VAR=value ...]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*## .*$$' Makefile | sort | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Configuration:"
	@echo "  Edit config.toml for project, L1, and VM configuration"
	@echo "  Create .env with L1_API_KEY (see .env.example)"
	@echo ""
	@echo "Variables:"
	@echo "  VM             Filter to specific VM name (optional)"
	@echo "  SNAPSHOT       Snapshot name for delete-snapshot (required)"
	@echo "  RETH_COMMIT    Override git commit for build (optional)"
	@echo ""
	@echo "Workflow (with golden snapshot):"
	@echo "  1. make create-l1                    # Create L1 node (one-time, takes days)"
	@echo "  2. Create API key in GCP Console, add to .env"
	@echo "  3. make build-reth && make build-op-node"
	@echo "  4. Sync a VM to desired block height (manual)"
	@echo "  5. make create-snapshot VM=<name>    # Create golden snapshot"
	@echo "  6. Edit config.toml: set [snapshot] name and [[vm]] sections"
	@echo "  7. make provision                    # Create VMs (disks from snapshot)"
	@echo "  8. make configure                    # Configure VMs (LSSD: rsync from temp disk)"
	@echo "  9. make benchmark VM=<name>          # Run benchmark"
	@echo "  10. make cleanup                     # Destroy VMs"
	@echo ""
	@echo "Golden Snapshot Management:"
	@echo "  make list-snapshots                  # List available golden snapshots"
	@echo "  make create-snapshot VM=<name>       # Create new snapshot from synced VM"
	@echo "  make delete-snapshot SNAPSHOT=<name> # Delete old snapshot"
	@echo ""
	@echo "Single VM operations:"
	@echo "  make provision VM=<name>             # Create specific VM"
	@echo "  make configure VM=<name>             # Configure specific VM"
	@echo "  make configure-status VM=<name>      # Check VM status"
	@echo "  make cleanup VM=<name>               # Destroy specific VM"
