#!/usr/bin/env bash
# =============================================================================
# Build Management
# =============================================================================
# Usage: build.sh {reth|op-node|status} [options]
# =============================================================================
source "$(dirname "$0")/common.sh"

ACTION="${1:-}"
shift || true
parse_flags "$@"

show_usage() {
    cat << 'EOF'
Usage: build.sh {reth|op-node|status} [options]

Commands:
  reth [--commit=<sha>]   Build op-reth binary from source
  op-node                 Build op-node binary (extract from Docker)
  status <type>           Show status of most recent build

Options:
  --commit=<sha>  Override git commit for reth build
  --type=<type>   Build type for status (configure|provision|benchmark|...)

Examples:
  build.sh reth                      # Build from configured branch
  build.sh reth --commit=abc123      # Build specific commit
  build.sh op-node                   # Build op-node
  build.sh status configure          # Show configure build status
EOF
    exit 1
}

[[ -z "$ACTION" ]] && show_usage

load_config

case "$ACTION" in
    reth)
        header "Building op-reth"
        echo "Repo:   $RETH_REPO"
        echo "Branch: $RETH_BRANCH"
        [[ -n "$RETH_COMMIT" ]] && echo "Commit: $RETH_COMMIT"
        echo ""
        
        submit_build "cloudbuild/builds/op-reth.yaml" \
            "_RETH_REPO=$RETH_REPO,_RETH_BRANCH=$RETH_BRANCH,_RETH_COMMIT=$RETH_COMMIT,_GCS_BUCKET=$GCS_BUCKET"
        ;;
        
    op-node)
        header "Building op-node"
        echo "Version: $OP_NODE_VERSION"
        echo ""
        
        submit_build "cloudbuild/builds/op-node.yaml" \
            "_OP_NODE_VERSION=$OP_NODE_VERSION,_GCS_BUCKET=$GCS_BUCKET"
        ;;
        
    status)
        TYPE="${TYPE:-${POSITIONAL_ARGS[0]:-}}"
        
        if [[ -z "$TYPE" ]]; then
            echo "Usage: build.sh status <type>"
            echo ""
            echo "Types: configure, provision, benchmark, build, cleanup, create-l1, destroy-l1"
            exit 1
        fi
        
        header "$TYPE Build Status"
        
        # Determine if this build type uses regional builds
        REGION_FLAG=""
        case "$TYPE" in
            configure|benchmark)
                REGION_FLAG="--region=$REGION"
                ;;
        esac
        
        # Find most recent build with this tag
        BUILD_ID=$(gcloud builds list \
            --project="$PROJECT_ID" \
            $REGION_FLAG \
            --filter="tags='$TYPE'" \
            --format="value(id)" \
            --limit=1 2>/dev/null)
        
        if [[ -z "$BUILD_ID" ]]; then
            echo "No $TYPE builds found"
            exit 0
        fi
        
        echo "Build ID: $BUILD_ID"
        
        gcloud builds describe "$BUILD_ID" \
            --project="$PROJECT_ID" \
            $REGION_FLAG \
            --format="table(status,createTime,finishTime)"
        
        echo ""
        
        STATUS=$(gcloud builds describe "$BUILD_ID" \
            --project="$PROJECT_ID" \
            $REGION_FLAG \
            --format="value(status)")
        
        if [[ "$STATUS" == "WORKING" ]]; then
            info "Build is running. Stream logs with:"
            echo "  gcloud builds log $BUILD_ID --project=$PROJECT_ID $REGION_FLAG --stream"
        else
            echo "View logs with:"
            echo "  gcloud builds log $BUILD_ID --project=$PROJECT_ID $REGION_FLAG"
        fi
        ;;
        
    *)
        error "Unknown action: $ACTION"
        show_usage
        ;;
esac
