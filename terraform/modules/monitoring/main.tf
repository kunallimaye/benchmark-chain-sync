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
# Log-Based Metrics - Extract real-time stage info from op-reth logs
# -----------------------------------------------------------------------------
# Note: Requires NO_COLOR=1 in op-reth service for clean log parsing.
# Counts Status log entries per stage, emitted every ~25 seconds.
# Use rate() to determine which stage is currently active:
#   topk(1, rate(logging.googleapis.com/user/reth_stage_log_count[5m])) by (vm_name, stage)
# -----------------------------------------------------------------------------
resource "google_logging_metric" "reth_stage_log_count" {
  name        = "reth_stage_log_count"
  project     = var.project_id
  description = "Count of Status log entries per stage from op-reth (use rate to find active stage)"

  filter = <<-EOF
    resource.type="gce_instance"
    textPayload=~"Status.*stage="
  EOF

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"

    labels {
      key         = "stage"
      value_type  = "STRING"
      description = "Pipeline stage from log"
    }
    labels {
      key         = "vm_name"
      value_type  = "STRING"
      description = "VM instance name"
    }
  }

  label_extractors = {
    "stage"   = "REGEXP_EXTRACT(textPayload, \"stage=(\\\\w+)\")"
    "vm_name" = "EXTRACT(resource.labels.instance_id)"
  }
}

# -----------------------------------------------------------------------------
# Dashboard - Key Performance Metrics by Stage Category (Overview)
# -----------------------------------------------------------------------------
# Layout:
#   Row 1: Chain Overview (4 scorecards) - L2 Tip, Chain Growth min/avg/max
#   Row 2: Execution Stages - Throughput, Checkpoint, ETA (height=20)
#   Row 3: Hashing Stages - Throughput, Checkpoint, ETA (height=20)
#   Row 4: History Indexing Stages - Throughput, Checkpoint, ETA (height=20)
#   Row 5: Execution Throughput (MGas/s) - All VMs
#   Row 6: VM Sync Status (table) - Combined table (experimental)
#
# Stage Categories:
#   - Execution: Execution
#   - Hashing: AccountHashing, StorageHashing, MerkleExecute
#   - History Indexing: TransactionLookup, IndexStorageHistory, IndexAccountHistory
#
# See also: op-reth Benchmark v1 dashboard for detailed stage analysis
# -----------------------------------------------------------------------------
resource "google_monitoring_dashboard" "reth_benchmark" {
  dashboard_json = jsonencode({
    displayName = "op-reth Benchmark"

    mosaicLayout = {
      columns = 48
      tiles = concat(
        local.scorecard_tiles,
        local.execution_stage_tiles,
        local.hashing_stage_tiles,
        local.history_indexing_stage_tiles,
        local.throughput_gas_tiles,
        local.table_tiles
      )
    }
  })

  depends_on = [google_project_service.telemetry]
}

# -----------------------------------------------------------------------------
# Dashboard Widget Definitions
# -----------------------------------------------------------------------------
locals {
  # Row 1: Chain Overview Scorecards (4 widgets)
  # Layout: 4 scorecards at 12 columns each (total 48)
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

  # Row 6: VM Sync Status Table (experimental - combined table)
  table_tiles = [
    {
      xPos   = 0
      yPos   = 80
      width  = 48
      height = 16
      widget = {
        title = "VM Sync Status (Execution)"
        timeSeriesTable = {
          dataSets = [
            {
              timeSeriesQuery = {
                prometheusQuery = "rate(reth_sync_checkpoint{stage=\"Execution\"}[5m])"
              }
              tableTemplate      = "{{vm_name}}"
              minAlignmentPeriod = "60s"
            },
            {
              timeSeriesQuery = {
                prometheusQuery = "reth_sync_checkpoint{stage=\"Execution\"}"
              }
              minAlignmentPeriod = "60s"
            },
            {
              timeSeriesQuery = {
                # ETA = blocks_remaining / (blocks_per_second * 3600)
                prometheusQuery = "(max(op_node_default_refs_number{layer=\"l2\",type=\"l2_unsafe\"}) - reth_sync_checkpoint{stage=\"Execution\"}) / (rate(reth_sync_checkpoint{stage=\"Execution\"}[15m]) * 3600)"
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
              displayName = "Throughput (blocks/s)"
            }
          ]
        }
      }
    }
  ]

  # ---------------------------------------------------------------------------
  # Row 2: Execution Stages
  # Stages: Execution
  # ---------------------------------------------------------------------------
  execution_stage_tiles = [
    # Throughput table (left)
    {
      xPos   = 0
      yPos   = 8
      width  = 16
      height = 20
      widget = {
        title = "Execution: Throughput (blocks/s)"
        timeSeriesTable = {
          dataSets = [
            {
              timeSeriesQuery = {
                prometheusQuery = "rate(reth_sync_checkpoint{stage=\"Execution\"}[5m])"
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
              displayName = "blocks/s"
            }
          ]
        }
      }
    },
    # Checkpoint table (center)
    {
      xPos   = 16
      yPos   = 8
      width  = 16
      height = 20
      widget = {
        title = "Execution: Checkpoint (block #)"
        timeSeriesTable = {
          dataSets = [
            {
              timeSeriesQuery = {
                prometheusQuery = "reth_sync_checkpoint{stage=\"Execution\"}"
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
    {
      xPos   = 32
      yPos   = 8
      width  = 16
      height = 20
      widget = {
        title = "Execution: ETA (hours)"
        timeSeriesTable = {
          dataSets = [
            {
              timeSeriesQuery = {
                # ETA = blocks_remaining / (blocks_per_second * 3600)
                # Uses on(vm_name) to match labels between op_node and reth metrics
                prometheusQuery = "(op_node_default_refs_number{layer=\"l2\",type=\"l2_unsafe\"} - on(vm_name) reth_sync_checkpoint{stage=\"Execution\"}) / on(vm_name) (rate(reth_sync_checkpoint{stage=\"Execution\"}[15m]) * 3600)"
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

  # ---------------------------------------------------------------------------
  # Row 3: Hashing Stages
  # Stages: AccountHashing, StorageHashing, MerkleExecute
  # Uses min without(stage) to show bottleneck (least-progressed stage)
  # ---------------------------------------------------------------------------
  hashing_stage_tiles = [
    # Throughput table (left)
    {
      xPos   = 0
      yPos   = 28
      width  = 16
      height = 20
      widget = {
        title = "Hashing: Throughput (blocks/s)"
        timeSeriesTable = {
          dataSets = [
            {
              timeSeriesQuery = {
                prometheusQuery = "min without(stage) (rate(reth_sync_checkpoint{stage=~\"AccountHashing|StorageHashing|MerkleExecute\"}[5m]))"
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
              displayName = "blocks/s"
            }
          ]
        }
      }
    },
    # Checkpoint table (center)
    {
      xPos   = 16
      yPos   = 28
      width  = 16
      height = 20
      widget = {
        title = "Hashing: Checkpoint (block #)"
        timeSeriesTable = {
          dataSets = [
            {
              timeSeriesQuery = {
                prometheusQuery = "min without(stage) (reth_sync_checkpoint{stage=~\"AccountHashing|StorageHashing|MerkleExecute\"})"
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
    {
      xPos   = 32
      yPos   = 28
      width  = 16
      height = 20
      widget = {
        title = "Hashing: ETA (hours)"
        timeSeriesTable = {
          dataSets = [
            {
              timeSeriesQuery = {
                # ETA = blocks_remaining / (blocks_per_second * 3600)
                # Uses min without(stage) to get bottleneck stage per VM
                prometheusQuery = "(op_node_default_refs_number{layer=\"l2\",type=\"l2_unsafe\"} - on(vm_name) min without(stage) (reth_sync_checkpoint{stage=~\"AccountHashing|StorageHashing|MerkleExecute\"})) / on(vm_name) (min without(stage) (rate(reth_sync_checkpoint{stage=~\"AccountHashing|StorageHashing|MerkleExecute\"}[15m])) * 3600)"
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

  # ---------------------------------------------------------------------------
  # Row 4: History Indexing Stages
  # Stages: TransactionLookup, IndexStorageHistory, IndexAccountHistory
  # Uses min without(stage) to show bottleneck (least-progressed stage)
  # ---------------------------------------------------------------------------
  history_indexing_stage_tiles = [
    # Throughput table (left)
    {
      xPos   = 0
      yPos   = 48
      width  = 16
      height = 20
      widget = {
        title = "History: Throughput (blocks/s)"
        timeSeriesTable = {
          dataSets = [
            {
              timeSeriesQuery = {
                prometheusQuery = "min without(stage) (rate(reth_sync_checkpoint{stage=~\"TransactionLookup|IndexStorageHistory|IndexAccountHistory\"}[5m]))"
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
              displayName = "blocks/s"
            }
          ]
        }
      }
    },
    # Checkpoint table (center)
    {
      xPos   = 16
      yPos   = 48
      width  = 16
      height = 20
      widget = {
        title = "History: Checkpoint (block #)"
        timeSeriesTable = {
          dataSets = [
            {
              timeSeriesQuery = {
                prometheusQuery = "min without(stage) (reth_sync_checkpoint{stage=~\"TransactionLookup|IndexStorageHistory|IndexAccountHistory\"})"
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
    {
      xPos   = 32
      yPos   = 48
      width  = 16
      height = 20
      widget = {
        title = "History: ETA (hours)"
        timeSeriesTable = {
          dataSets = [
            {
              timeSeriesQuery = {
                # ETA = blocks_remaining / (blocks_per_second * 3600)
                # Uses min without(stage) to get bottleneck stage per VM
                prometheusQuery = "(op_node_default_refs_number{layer=\"l2\",type=\"l2_unsafe\"} - on(vm_name) min without(stage) (reth_sync_checkpoint{stage=~\"TransactionLookup|IndexStorageHistory|IndexAccountHistory\"})) / on(vm_name) (min without(stage) (rate(reth_sync_checkpoint{stage=~\"TransactionLookup|IndexStorageHistory|IndexAccountHistory\"}[15m])) * 3600)"
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

  # ---------------------------------------------------------------------------
  # Row 5: Execution Throughput (MGas/s) - All VMs on one chart
  # ---------------------------------------------------------------------------
  throughput_gas_tiles = [
    {
      xPos   = 0
      yPos   = 68
      width  = 48
      height = 12
      widget = {
        title = "Execution Throughput (MGas/s)"
        xyChart = {
          dataSets = [{
            timeSeriesQuery = {
              prometheusQuery = "reth_sync_execution_gas_per_second / 1000000"
            }
            plotType       = "LINE"
            legendTemplate = "{{vm_name}}"
          }]
        }
      }
    }
  ]

  # ===========================================================================
  # V1 Dashboard Tiles (Detailed Stage Analysis)
  # ===========================================================================
  # These tiles are used in the op-reth Benchmark v1 dashboard.
  # yPos values start from 0 for the v1 dashboard layout.
  # ===========================================================================

  # ---------------------------------------------------------------------------
  # V1 Row 1: Time Spent Per Stage (stacked area chart)
  # ---------------------------------------------------------------------------
  # Shows cumulative time spent in each pipeline stage per VM.
  # Useful for understanding where time is being spent during sync.
  # ---------------------------------------------------------------------------
  v1_time_breakdown_tiles = [
    {
      xPos   = 0
      yPos   = 0
      width  = 48
      height = 16
      widget = {
        title = "Time Spent Per Stage (hours)"
        xyChart = {
          dataSets = [{
            timeSeriesQuery = {
              prometheusQuery = "reth_sync_total_elapsed / 3600"
            }
            plotType       = "STACKED_AREA"
            legendTemplate = "{{vm_name}} - {{stage}}"
          }]
          yAxis = {
            label = "Hours"
          }
        }
      }
    }
  ]

  # ---------------------------------------------------------------------------
  # V1 Row 2: All Stages Breakdown Table
  # ---------------------------------------------------------------------------
  # Shows checkpoint for all pipeline stages per VM.
  # Provides detailed view of which stage each VM is in.
  # ---------------------------------------------------------------------------
  v1_stage_breakdown_tiles = [
    {
      xPos   = 0
      yPos   = 16
      width  = 48
      height = 20
      widget = {
        title = "All Stages: Checkpoint (block #)"
        timeSeriesTable = {
          dataSets = [
            {
              timeSeriesQuery = {
                prometheusQuery = "reth_sync_checkpoint"
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
              column      = "stage"
              visible     = true
              displayName = "Stage"
            },
            {
              column      = "value"
              visible     = true
              displayName = "Checkpoint"
            }
          ]
        }
      }
    }
  ]
}

# -----------------------------------------------------------------------------
# Dashboard V1 - Detailed Stage Analysis
# -----------------------------------------------------------------------------
# Layout:
#   Row 1: Time Spent Per Stage (stacked area chart) - yPos=0, height=16
#   Row 2: All Stages Breakdown Table - yPos=16, height=20
#
# This dashboard provides detailed stage-level visibility for debugging
# and deep analysis of sync performance.
# -----------------------------------------------------------------------------
resource "google_monitoring_dashboard" "reth_benchmark_v1" {
  dashboard_json = jsonencode({
    displayName = "op-reth Benchmark v1"

    mosaicLayout = {
      columns = 48
      tiles = concat(
        local.v1_time_breakdown_tiles,
        local.v1_stage_breakdown_tiles
      )
    }
  })

  depends_on = [google_project_service.telemetry]
}
