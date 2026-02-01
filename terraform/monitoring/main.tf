# =============================================================================
# Cloud Monitoring Dashboard for op-reth Benchmarks
# =============================================================================

# -----------------------------------------------------------------------------
# Enable Telemetry API (required for Cloud Trace OTLP ingestion)
# -----------------------------------------------------------------------------
resource "google_project_service" "telemetry" {
  project = var.project_id
  service = "telemetry.googleapis.com"

  disable_on_destroy = false
}

# -----------------------------------------------------------------------------
# Log-based Distribution Metric for Stage Progress Rate Calculation
# Extracts stage_progress percentage as numeric value for rate() computation
# Only MerkleExecute (and sometimes Execution) emit stage_progress in logs
# -----------------------------------------------------------------------------
resource "google_logging_metric" "reth_stage_progress_distribution" {
  name        = "reth_stage_progress_distribution"
  project     = var.project_id
  description = "Stage progress percentage as distribution for real-time progress tracking"

  filter = <<-EOF
    resource.type="gce_instance"
    textPayload=~"Status.*stage_progress="
  EOF

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "DISTRIBUTION"
    unit        = "1"

    labels {
      key         = "vm_name"
      value_type  = "STRING"
      description = "VM hostname"
    }
    labels {
      key         = "stage"
      value_type  = "STRING"
      description = "Pipeline stage name"
    }
  }

  # Extract stage_progress percentage as the metric VALUE (e.g., 35.43)
  value_extractor = "REGEXP_EXTRACT(textPayload, \"stage_progress=([\\\\d.]+)\")"

  label_extractors = {
    "vm_name" = "REGEXP_EXTRACT(textPayload, \"\\\\+00:00 ([\\\\w-]+) op-reth\")"
    "stage"   = "REGEXP_EXTRACT(textPayload, \"stage=(\\\\w+)\")"
  }

  # Linear buckets from 0-100% with 1% width
  bucket_options {
    linear_buckets {
      num_finite_buckets = 100
      width              = 1
      offset             = 0
    }
  }
}

# -----------------------------------------------------------------------------
# Dashboard Widget Definitions
# -----------------------------------------------------------------------------
locals {
  # VM filter pattern for dashboard
  vm_filter = "vm_name=~\"op-reth.*|c4-.*\""

  # Row 1: Chain Overview Scorecards
  scorecard_tiles = [
    {
      xPos   = 0
      yPos   = 0
      width  = 12
      height = 8
      widget = {
        title = "L2 Tip (Unsafe Head)"
        scorecard = {
          timeSeriesQuery = {
            prometheusQuery = "max(op_node_default_refs_number{layer=\"l2\",type=\"l2_unsafe\"})"
          }
        }
      }
    },
    {
      xPos   = 12
      yPos   = 0
      width  = 12
      height = 8
      widget = {
        title = "Chain Growth Min (blocks/s)"
        scorecard = {
          timeSeriesQuery = {
            prometheusQuery = "min(rate(op_node_default_refs_number{layer=\"l2\",type=\"l2_unsafe\"}[5m]))"
          }
        }
      }
    },
    {
      xPos   = 24
      yPos   = 0
      width  = 12
      height = 8
      widget = {
        title = "Chain Growth Avg (blocks/s)"
        scorecard = {
          timeSeriesQuery = {
            prometheusQuery = "avg(rate(op_node_default_refs_number{layer=\"l2\",type=\"l2_unsafe\"}[5m]))"
          }
        }
      }
    },
    {
      xPos   = 36
      yPos   = 0
      width  = 12
      height = 8
      widget = {
        title = "Chain Growth Max (blocks/s)"
        scorecard = {
          timeSeriesQuery = {
            prometheusQuery = "max(rate(op_node_default_refs_number{layer=\"l2\",type=\"l2_unsafe\"}[5m]))"
          }
        }
      }
    }
  ]

  # Stage definitions for dashboard
  # Each stage gets a row with Throughput, Checkpoint, and ETA tables
  #
  # throughput_type:
  #   - "checkpoint": rate(reth_sync_checkpoint) - blocks/s
  #   - "entities": rate(reth_sync_entities_processed) - entities/s
  #   - "progress": stage_progress distribution mean - shows progress %
  #
  # eta_type:
  #   - "entity": Uses entities_total/entities_processed (more accurate)
  #   - "checkpoint": Uses L2_tip/checkpoint (for stages without entities_total)
  #
  # Stages with entities_total > 0: Headers, Bodies, SenderRecovery, Execution,
  #   AccountHashing, StorageHashing, MerkleExecute, TransactionLookup
  # Stages with entities_total = 0: MerkleUnwind, IndexStorageHistory,
  #   IndexAccountHistory, Prune, Finish
  stages = [
    { num = "01", name = "Headers",              throughput_type = "checkpoint", eta_type = "entity" },
    { num = "02", name = "Bodies",               throughput_type = "checkpoint", eta_type = "entity" },
    { num = "03", name = "SenderRecovery",       throughput_type = "checkpoint", eta_type = "entity" },
    { num = "04", name = "Execution",            throughput_type = "entities",   eta_type = "entity" },
    { num = "05", name = "MerkleUnwind",         throughput_type = "checkpoint", eta_type = "checkpoint" },
    { num = "06", name = "AccountHashing",       throughput_type = "entities",   eta_type = "entity" },
    { num = "07", name = "StorageHashing",       throughput_type = "checkpoint", eta_type = "entity" },
    { num = "08", name = "MerkleExecute",        throughput_type = "progress",   eta_type = "entity" },
    { num = "09", name = "TransactionLookup",    throughput_type = "checkpoint", eta_type = "entity" },
    { num = "10", name = "IndexStorageHistory",  throughput_type = "checkpoint", eta_type = "checkpoint" },
    { num = "11", name = "IndexAccountHistory",  throughput_type = "checkpoint", eta_type = "checkpoint" },
    { num = "12", name = "Prune",                throughput_type = "checkpoint", eta_type = "checkpoint" },
    { num = "13", name = "Finish",               throughput_type = "checkpoint", eta_type = "checkpoint" },
  ]

  # Generate tiles for each stage (3 widgets per stage: Throughput, Checkpoint, ETA)
  # Row 1 is scorecards at yPos=0 height=8, stages start at yPos=8
  stage_tiles = flatten([
    for idx, stage in local.stages : [
      # Throughput table (left)
      # Uses different metrics based on stage type:
      #   - "checkpoint": rate(reth_sync_checkpoint) - blocks/s
      #   - "entities": rate(reth_sync_entities_processed) - entities/s
      #   - "progress": stage_progress distribution mean - shows progress %
      {
        xPos   = 0
        yPos   = 8 + (idx * 20)
        width  = 16
        height = 20
        widget = {
          title = stage.throughput_type == "progress" ? "${stage.num}-${stage.name}: Progress (%)" : "${stage.num}-${stage.name}: Throughput"
          timeSeriesTable = {
            dataSets = [
              {
                timeSeriesQuery = {
                  prometheusQuery = (
                    stage.throughput_type == "progress"
                    ? "logging_googleapis_com:user_reth_stage_progress_distribution_sum{stage=\"${stage.name}\", ${local.vm_filter}} / logging_googleapis_com:user_reth_stage_progress_distribution_count{stage=\"${stage.name}\", ${local.vm_filter}}"
                    : stage.throughput_type == "entities"
                    ? "rate(reth_sync_entities_processed{stage=\"${stage.name}\", ${local.vm_filter}}[5m])"
                    : "rate(reth_sync_checkpoint{stage=\"${stage.name}\", ${local.vm_filter}}[5m])"
                  )
                }
                minAlignmentPeriod = "60s"
              }
            ]
            metricVisualization = "NUMBER"
            columnSettings = [
              {
                column      = "vm_name"
                visible     = true
                displayName = "VM"
              },
              {
                column      = "value"
                visible     = true
                displayName = stage.throughput_type == "progress" ? "%" : stage.throughput_type == "entities" ? "entities/s" : "blocks/s"
              }
            ]
          }
        }
      },
      # Checkpoint table (center)
      {
        xPos   = 16
        yPos   = 8 + (idx * 20)
        width  = 16
        height = 20
        widget = {
          title = "${stage.num}-${stage.name}: Checkpoint (block #)"
          timeSeriesTable = {
            dataSets = [
              {
                timeSeriesQuery = {
                  prometheusQuery = "reth_sync_checkpoint{stage=\"${stage.name}\", ${local.vm_filter}}"
                }
                minAlignmentPeriod = "60s"
              }
            ]
            metricVisualization = "NUMBER"
            columnSettings = [
              {
                column      = "vm_name"
                visible     = true
                displayName = "VM"
              },
              {
                column      = "value"
                visible     = true
                displayName = "block #"
              }
            ]
          }
        }
      },
      # ETA table (right)
      # Uses entity-based or checkpoint-based calculation depending on stage
      # - Active stages (rate > 0.001): Show valid ETA in hours
      # - Inactive/Completed stages: Show -9999 (indicates "Not Available")
      # Uses boolean math: ETA * is_active + (-9999 * is_inactive)
      {
        xPos   = 32
        yPos   = 8 + (idx * 20)
        width  = 16
        height = 20
        widget = {
          title = "${stage.num}-${stage.name}: ETA (hours)"
          timeSeriesTable = {
            dataSets = [
              {
                timeSeriesQuery = {
                  prometheusQuery = (
                    stage.eta_type == "entity"
                    # Entity-based ETA: (ETA * is_active) + (-9999 * is_inactive)
                    ? "(((reth_sync_entities_total{stage=\"${stage.name}\", ${local.vm_filter}} - reth_sync_entities_processed{stage=\"${stage.name}\", ${local.vm_filter}}) / (rate(reth_sync_entities_processed{stage=\"${stage.name}\", ${local.vm_filter}}[15m]) * 3600)) * (rate(reth_sync_entities_processed{stage=\"${stage.name}\", ${local.vm_filter}}[15m]) > bool 0.001)) + ((-9999) * (rate(reth_sync_entities_processed{stage=\"${stage.name}\", ${local.vm_filter}}[15m]) <= bool 0.001))"
                    # Checkpoint-based ETA: (ETA * is_active) + (-9999 * is_inactive)
                    : "(((op_node_default_refs_number{layer=\"l2\",type=\"l2_unsafe\"} - on(vm_name) reth_sync_checkpoint{stage=\"${stage.name}\", ${local.vm_filter}}) / on(vm_name) clamp_min(rate(reth_sync_checkpoint{stage=\"${stage.name}\", ${local.vm_filter}}[15m]), 0.0001) / 3600) * on(vm_name) (rate(reth_sync_checkpoint{stage=\"${stage.name}\", ${local.vm_filter}}[15m]) > bool 0.001)) + on(vm_name) ((-9999) * (rate(reth_sync_checkpoint{stage=\"${stage.name}\", ${local.vm_filter}}[15m]) <= bool 0.001))"
                  )
                }
                minAlignmentPeriod = "60s"
              }
            ]
            metricVisualization = "NUMBER"
            columnSettings = [
              {
                column      = "vm_name"
                visible     = true
                displayName = "VM"
              },
              {
                column      = "value"
                visible     = true
                displayName = "hours"
              }
            ]
          }
        }
      }
    ]
  ])
}

# -----------------------------------------------------------------------------
# Dashboard Resource
# -----------------------------------------------------------------------------
resource "google_monitoring_dashboard" "reth_benchmark" {
  dashboard_json = jsonencode({
    displayName = "op-reth Benchmark"

    mosaicLayout = {
      columns = 48
      tiles = concat(
        local.scorecard_tiles,
        local.stage_tiles
      )
    }
  })

  depends_on = [google_project_service.telemetry]
}
