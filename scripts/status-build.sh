#!/usr/bin/env bash
# Show status of most recent build by type
source "$(dirname "$0")/common.sh"

TYPE="${1:-}"

load_config

if [[ -z "$TYPE" ]]; then
    echo "Usage: $0 <type>"
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
