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
#   4. make create-download-disk         # Create shared download disk (one-time)
#   5. make download                     # Download snapshot to shared disk
#   6. Edit config.toml with VM configs  # Define VMs to provision
#   7. make provision                    # Create all VMs (or VM=name for one)
#   8. make configure                    # Configure all VMs (or VM=name)
#   9. make benchmark VM=name            # Run benchmark on specific VM
#  10. make cleanup                      # Destroy all VMs (or VM=name)
# =============================================================================

.PHONY: build-reth build-op-node provision provision-plan configure benchmark \
        cleanup list-instances \
        create-l1 destroy-l1 status-l1 \
        create-download-disk download download-status delete-download-disk \
        status validate-terraform help \
        build-status configure-status benchmark-status extract-status

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

# Download disk name
DOWNLOAD_DISK_NAME := $(shell grep -A1 '^\[download\]' config.toml | grep 'disk_name' | cut -d'"' -f2)

# VM filter (optional - if set, only operate on this VM)
VM ?=

# =============================================================================
# L1 Infrastructure (BNE)
# =============================================================================

create-l1: ## Create L1 BNE node (takes days to sync!)
	@echo "=== Creating L1 Infrastructure (BNE) ==="
	@echo "Network: $(NETWORK) -> L1: $(L1_NETWORK)"
	@echo "WARNING: BNE nodes take several days to sync!"
	@echo ""
	gcloud builds submit . \
		--config=cloudbuild/create-l1.yaml \
		--project=$(PROJECT_ID) \
		--substitutions=_PROJECT_ID=$(PROJECT_ID),_REGION=$(REGION),_ZONE=$(ZONE),_NETWORK=$(NETWORK),_GCS_BUCKET=$(GCS_BUCKET),_L1_NETWORK=$(L1_NETWORK)

destroy-l1: ## Destroy L1 infrastructure (WARNING: re-sync takes days!)
	@echo "=== Destroying L1 Infrastructure ==="
	@echo "WARNING: Re-syncing BNE takes several days!"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	gcloud builds submit . \
		--config=cloudbuild/destroy-l1.yaml \
		--project=$(PROJECT_ID) \
		--substitutions=_PROJECT_ID=$(PROJECT_ID),_REGION=$(REGION),_ZONE=$(ZONE),_NETWORK=$(NETWORK),_GCS_BUCKET=$(GCS_BUCKET)

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
		--config=cloudbuild/build-op-reth.yaml \
		--project=$(PROJECT_ID) \
		--substitutions=_RETH_REPO=$(RETH_REPO),_RETH_BRANCH=$(RETH_BRANCH),_RETH_COMMIT=$(RETH_COMMIT),_GCS_BUCKET=$(GCS_BUCKET)

build-op-node: ## Build op-node binary (extracts from Docker image)
	@echo "=== Building op-node ==="
	@echo "Version: $(OP_NODE_VERSION)"
	@echo ""
	gcloud builds submit . \
		--config=cloudbuild/build-op-node.yaml \
		--project=$(PROJECT_ID) \
		--substitutions=_OP_NODE_VERSION=$(OP_NODE_VERSION),_GCS_BUCKET=$(GCS_BUCKET)

# =============================================================================
# Snapshot Download (Shared Disk)
# =============================================================================

create-download-disk: ## Create shared download disk (one-time)
	@echo "=== Creating Download Disk ==="
	@echo "Disk name: $(DOWNLOAD_DISK_NAME)"
	@echo ""
	gcloud builds submit . \
		--config=cloudbuild/create-download-disk.yaml \
		--project=$(PROJECT_ID) \
		--substitutions=_GCS_BUCKET=$(GCS_BUCKET)

download: ## Download snapshot to shared disk (async, ~2-3 hours)
	@echo "=== Downloading Snapshot ==="
	@echo "This will download the snapshot to the shared download disk."
	@echo "Any existing snapshot on the disk will be overwritten."
	@echo "Build runs async - use 'make download-status' to monitor."
	@echo ""
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	gcloud builds submit . \
		--config=cloudbuild/download.yaml \
		--project=$(PROJECT_ID) \
		--async

download-status: ## Check download progress
	@echo "=== Download Disk Status ==="
	@echo ""
	@echo "=== Disk Info ==="
	@gcloud compute disks describe $(DOWNLOAD_DISK_NAME) \
		--zone=$(ZONE) \
		--project=$(PROJECT_ID) \
		--format="table(name,sizeGb,status,type)" \
		2>/dev/null || echo "Download disk not found. Run 'make create-download-disk' first."
	@echo ""
	@echo "=== Downloader VM ==="
	@gcloud compute instances describe op-reth-downloader \
		--zone=$(ZONE) \
		--project=$(PROJECT_ID) \
		--format="table(name,status,machineType)" \
		2>/dev/null && \
		(echo "" && echo "=== Download Progress ===" && \
		gcloud compute ssh op-reth-downloader \
			--zone=$(ZONE) \
			--project=$(PROJECT_ID) \
			--command='cat /mnt/download/.download-status 2>/dev/null || echo "No status file yet"' \
			2>/dev/null) || \
		echo "Downloader VM not running (download complete or not started)"

delete-download-disk: ## Delete shared download disk (WARNING: permanent!)
	@echo "=== Deleting Download Disk ==="
	@echo "WARNING: This will permanently delete the download disk and any snapshot on it!"
	@echo ""
	@read -p "Type 'delete' to confirm: " confirm && [ "$$confirm" = "delete" ] || exit 1
	gcloud compute disks delete $(DOWNLOAD_DISK_NAME) \
		--zone=$(ZONE) \
		--project=$(PROJECT_ID) \
		--quiet

# =============================================================================
# Provision Infrastructure (Terraform only)
# =============================================================================

provision: ## Create VMs from config.toml (all VMs, or VM=name for specific)
	@if [ -z "$(L1_API_KEY)" ]; then \
		echo "ERROR: L1_API_KEY is required"; \
		echo "Create .env file with L1_API_KEY=... (see .env.example)"; \
		exit 1; \
	fi
	@echo "=== Provisioning Infrastructure ==="
	@if [ -n "$(VM)" ]; then \
		echo "VM Filter: $(VM)"; \
	else \
		echo "VMs: all from config.toml"; \
	fi
	@echo ""
	gcloud builds submit . \
		--config=cloudbuild/provision.yaml \
		--project=$(PROJECT_ID) \
		--substitutions=_GCS_BUCKET=$(GCS_BUCKET),_L1_API_KEY=$(L1_API_KEY),_VM=$(VM) \
		--async 

provision-plan: ## Dry-run provision (terraform plan, no apply)
	@if [ -z "$(L1_API_KEY)" ]; then \
		echo "ERROR: L1_API_KEY is required"; \
		echo "Create .env file with L1_API_KEY=... (see .env.example)"; \
		exit 1; \
	fi
	@echo "=== Provisioning Plan (dry-run) ==="
	@if [ -n "$(VM)" ]; then \
		echo "VM Filter: $(VM)"; \
	else \
		echo "VMs: all from config.toml"; \
	fi
	@echo ""
	gcloud builds submit . \
		--config=cloudbuild/provision.yaml \
		--project=$(PROJECT_ID) \
		--substitutions=_GCS_BUCKET=$(GCS_BUCKET),_L1_API_KEY=$(L1_API_KEY),_VM=$(VM),_PLAN_ONLY=true

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
		--config=cloudbuild/configure.yaml \
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

configure-status: ## Show configure/extract status for a VM (requires VM=name)
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
		echo "=== Extract Status ==="; \
		if [ -f /mnt/data/.extract-status ]; then \
			cat /mnt/data/.extract-status | jq . 2>/dev/null || cat /mnt/data/.extract-status; \
		else \
			echo "No extract status file found"; \
		fi; \
		echo ""; \
		echo "=== Download Disk ==="; \
		if [ -d /mnt/download ]; then \
			if [ -f /mnt/download/snapshot.tar.zst ]; then \
				ls -lh /mnt/download/snapshot.tar.zst; \
			else \
				echo "Snapshot file not found on download disk"; \
			fi; \
		else \
			echo "Download disk not mounted"; \
		fi; \
		echo ""; \
		echo "=== Services ==="; \
		systemctl is-active snapshot-extract.service 2>/dev/null && echo "snapshot-extract: RUNNING" || echo "snapshot-extract: not running"; \
		systemctl is-active op-reth.service 2>/dev/null && echo "op-reth: RUNNING" || echo "op-reth: not running"; \
		systemctl is-active op-node.service 2>/dev/null && echo "op-node: RUNNING" || echo "op-node: not running"; \
		echo ""; \
		echo "=== Data Directory ==="; \
		if [ -f /mnt/data/op-reth/db/mdbx.dat ]; then \
			echo "Database exists"; \
			du -sh /mnt/data/op-reth/db 2>/dev/null || true; \
		else \
			echo "Database not found (extraction may be in progress)"; \
		fi; \
		echo ""; \
		echo "=== Recent Logs (snapshot-extract) ==="; \
		journalctl -u snapshot-extract.service -n 5 --no-pager 2>/dev/null || echo "No logs available"; \
	' 2>/dev/null || echo "ERROR: Could not SSH to $(VM). VM may not exist or SSH may not be ready."

extract-status: ## Alias for configure-status (requires VM=name)
	@$(MAKE) configure-status VM=$(VM)

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
		--config=cloudbuild/run-benchmark.yaml \
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
		--config=cloudbuild/cleanup.yaml \
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
	@echo "=== Download Disk ==="
	@gcloud compute disks describe $(DOWNLOAD_DISK_NAME) \
		--zone=$(ZONE) \
		--project=$(PROJECT_ID) \
		--format="value(name,sizeGb,status)" \
		2>/dev/null && echo " GB" || echo "  Not found"
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
	@echo "  RETH_COMMIT    Override git commit for build (optional)"
	@echo ""
	@echo "New Workflow (with shared download disk):"
	@echo "  1. make create-l1                    # Create L1 node (one-time, takes days)"
	@echo "  2. Create API key in GCP Console, add to .env"
	@echo "  3. make create-download-disk         # Create shared download disk (one-time)"
	@echo "  4. make download                     # Download snapshot (once per snapshot version)"
	@echo "  5. Edit config.toml with [[vm]] sections"
	@echo "  6. make provision                    # Create all VMs"
	@echo "  7. make configure                    # Configure all VMs (parallel extraction!)"
	@echo "  8. make benchmark VM=<name>"
	@echo "  9. make cleanup                      # Destroy all VMs (keeps download disk)"
	@echo ""
	@echo "Single VM operations:"
	@echo "  make provision VM=<name>             # Create specific VM"
	@echo "  make configure VM=<name>             # Configure specific VM"
	@echo "  make configure-status VM=<name>      # Check extraction progress"
	@echo "  make cleanup VM=<name>               # Destroy specific VM"
