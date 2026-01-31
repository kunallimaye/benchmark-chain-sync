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
# Note: Requires --color never in op-reth service for clean log parsing.
# Counts Status log entries per stage, emitted every ~25 seconds.
#
# Log format example:
#   INFO Status connected_peers=15 stage=MerkleExecute checkpoint=40840749 target=41368260 stage_progress=47.55% stage_eta=3h14m20s
#
# Query for active stage with ETA:
#   {__name__="logging.googleapis.com/user/reth_stage_log_count", vm_name=~"op-reth.*|c4-.*", stage_eta!=""}
# -----------------------------------------------------------------------------
resource "google_logging_metric" "reth_stage_log_count" {
  name        = "reth_stage_log_count"
  project     = var.project_id
  description = "Status log entries from op-reth with stage, checkpoint, target, progress, and ETA"

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
      description = "Pipeline stage name"
    }
    labels {
      key         = "vm_name"
      value_type  = "STRING"
      description = "VM hostname"
    }
    labels {
      key         = "checkpoint"
      value_type  = "STRING"
      description = "Current block number for the stage"
    }
    labels {
      key         = "target"
      value_type  = "STRING"
      description = "Target block number"
    }
    labels {
      key         = "stage_progress"
      value_type  = "STRING"
      description = "Stage progress percentage (empty if not available)"
    }
    labels {
      key         = "stage_eta"
      value_type  = "STRING"
      description = "Estimated time remaining for stage (empty if not available)"
    }
  }

  label_extractors = {
    # Extract VM hostname from syslog prefix: "<timestamp>+00:00 <hostname> op-reth[pid]:"
    "vm_name"        = "REGEXP_EXTRACT(textPayload, \"\\\\+00:00 ([\\\\w-]+) op-reth\")"
    "stage"          = "REGEXP_EXTRACT(textPayload, \"stage=(\\\\w+)\")"
    "checkpoint"     = "REGEXP_EXTRACT(textPayload, \"checkpoint=(\\\\d+)\")"
    "target"         = "REGEXP_EXTRACT(textPayload, \"target=(\\\\d+)\")"
    "stage_progress" = "REGEXP_EXTRACT(textPayload, \"stage_progress=([\\\\d.]+)\")"
    "stage_eta"      = "REGEXP_EXTRACT(textPayload, \"stage_eta=([\\\\dhms]+)\")"
  }
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
  # V1 Dashboard Tiles (Entity-Based Sync Status with Stage Sequence Numbers)
  # ===========================================================================
  # Uses reth_sync_entities_processed for accurate progress tracking.
  # Stage names are prefixed with sequence numbers (01-13) for sorting.
  #
  # Stage sequence and entity types:
  #   01-Headers:             blocks
  #   02-Bodies:              blocks
  #   03-SenderRecovery:      transactions
  #   04-Execution:           gas units
  #   05-MerkleUnwind:        (cleanup)
  #   06-AccountHashing:      accounts
  #   07-StorageHashing:      storage slots
  #   08-MerkleExecute:       trie nodes
  #   09-TransactionLookup:   transactions
  #   10-IndexStorageHistory: history entries
  #   11-IndexAccountHistory: history entries
  #   12-Prune:               (cleanup)
  #   13-Finish:              (finalization)
  #
  # Layout:
  #   Row 1: Active Stages (entities/s > 0)     - yPos=0,  height=16
  #   Row 2: All Stages - Progress %            - yPos=16, height=24
  #   Row 3: All Stages - Throughput (entities) - yPos=40, height=24
  #   Row 4: All Stages - ETA (hours)           - yPos=64, height=24
  #   Row 5: All Stages - Checkpoint            - yPos=88, height=20
  #   Row 6: Progress Chart                     - yPos=108, height=16
  # ===========================================================================

  # ---------------------------------------------------------------------------
  # Helper: Stage label_replace chain for reth_sync_entities_processed
  # ---------------------------------------------------------------------------
  # Adds sequence numbers to stage labels for proper sorting.
  # Format: label_replace(..., "stage", "XX-StageName", "stage", ".*")
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # V1 Row 1: Active Stages (entities/s > 0)
  # ---------------------------------------------------------------------------
  v1_active_stages_tiles = [
    {
      xPos   = 0
      yPos   = 0
      width  = 48
      height = 16
      widget = {
        title = "Active Stages (processing now)"
        timeSeriesTable = {
          dataSets = [
            {
              timeSeriesQuery = {
                # NOTE: label_replace must be applied AFTER rate() in Cloud Monitoring
                prometheusQuery = <<-EOT
label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(
  rate(reth_sync_entities_processed{vm_name=~"op-reth.*|c4-.*"}[5m]),
  "stage", "01-Headers", "stage", "^Headers$"),
  "stage", "02-Bodies", "stage", "^Bodies$"),
  "stage", "03-SenderRecovery", "stage", "^SenderRecovery$"),
  "stage", "04-Execution", "stage", "^Execution$"),
  "stage", "05-MerkleUnwind", "stage", "^MerkleUnwind$"),
  "stage", "06-AccountHashing", "stage", "^AccountHashing$"),
  "stage", "07-StorageHashing", "stage", "^StorageHashing$"),
  "stage", "08-MerkleExecute", "stage", "^MerkleExecute$"),
  "stage", "09-TransactionLookup", "stage", "^TransactionLookup$"),
  "stage", "10-IndexStorageHistory", "stage", "^IndexStorageHistory$"),
  "stage", "11-IndexAccountHistory", "stage", "^IndexAccountHistory$"),
  "stage", "12-Prune", "stage", "^Prune$"),
  "stage", "13-Finish", "stage", "^Finish$")
> 0
EOT
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
              displayName = "entities/s"
            }
          ]
        }
      }
    }
  ]

  # ---------------------------------------------------------------------------
  # V1 Row 2: All Stages - Progress %
  # ---------------------------------------------------------------------------
  v1_progress_pct_tiles = [
    {
      xPos   = 0
      yPos   = 16
      width  = 48
      height = 24
      widget = {
        title = "All Stages: Progress %"
        timeSeriesTable = {
          dataSets = [
            {
              timeSeriesQuery = {
                prometheusQuery = <<-EOT
label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(
  reth_sync_entities_processed{vm_name=~"op-reth.*|c4-.*"},
  "stage", "01-Headers", "stage", "^Headers$"),
  "stage", "02-Bodies", "stage", "^Bodies$"),
  "stage", "03-SenderRecovery", "stage", "^SenderRecovery$"),
  "stage", "04-Execution", "stage", "^Execution$"),
  "stage", "05-MerkleUnwind", "stage", "^MerkleUnwind$"),
  "stage", "06-AccountHashing", "stage", "^AccountHashing$"),
  "stage", "07-StorageHashing", "stage", "^StorageHashing$"),
  "stage", "08-MerkleExecute", "stage", "^MerkleExecute$"),
  "stage", "09-TransactionLookup", "stage", "^TransactionLookup$"),
  "stage", "10-IndexStorageHistory", "stage", "^IndexStorageHistory$"),
  "stage", "11-IndexAccountHistory", "stage", "^IndexAccountHistory$"),
  "stage", "12-Prune", "stage", "^Prune$"),
  "stage", "13-Finish", "stage", "^Finish$")
/
label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(
  reth_sync_entities_total{vm_name=~"op-reth.*|c4-.*"},
  "stage", "01-Headers", "stage", "^Headers$"),
  "stage", "02-Bodies", "stage", "^Bodies$"),
  "stage", "03-SenderRecovery", "stage", "^SenderRecovery$"),
  "stage", "04-Execution", "stage", "^Execution$"),
  "stage", "05-MerkleUnwind", "stage", "^MerkleUnwind$"),
  "stage", "06-AccountHashing", "stage", "^AccountHashing$"),
  "stage", "07-StorageHashing", "stage", "^StorageHashing$"),
  "stage", "08-MerkleExecute", "stage", "^MerkleExecute$"),
  "stage", "09-TransactionLookup", "stage", "^TransactionLookup$"),
  "stage", "10-IndexStorageHistory", "stage", "^IndexStorageHistory$"),
  "stage", "11-IndexAccountHistory", "stage", "^IndexAccountHistory$"),
  "stage", "12-Prune", "stage", "^Prune$"),
  "stage", "13-Finish", "stage", "^Finish$")
* 100
EOT
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
              displayName = "Progress %"
            }
          ]
        }
      }
    }
  ]

  # ---------------------------------------------------------------------------
  # V1 Row 3: All Stages - Throughput (entities/s)
  # ---------------------------------------------------------------------------
  v1_throughput_tiles = [
    {
      xPos   = 0
      yPos   = 40
      width  = 48
      height = 24
      widget = {
        title = "All Stages: Throughput (entities/s)"
        timeSeriesTable = {
          dataSets = [
            {
              timeSeriesQuery = {
                # NOTE: label_replace must be applied AFTER rate() in Cloud Monitoring
                prometheusQuery = <<-EOT
label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(
  rate(reth_sync_entities_processed{vm_name=~"op-reth.*|c4-.*"}[5m]),
  "stage", "01-Headers", "stage", "^Headers$"),
  "stage", "02-Bodies", "stage", "^Bodies$"),
  "stage", "03-SenderRecovery", "stage", "^SenderRecovery$"),
  "stage", "04-Execution", "stage", "^Execution$"),
  "stage", "05-MerkleUnwind", "stage", "^MerkleUnwind$"),
  "stage", "06-AccountHashing", "stage", "^AccountHashing$"),
  "stage", "07-StorageHashing", "stage", "^StorageHashing$"),
  "stage", "08-MerkleExecute", "stage", "^MerkleExecute$"),
  "stage", "09-TransactionLookup", "stage", "^TransactionLookup$"),
  "stage", "10-IndexStorageHistory", "stage", "^IndexStorageHistory$"),
  "stage", "11-IndexAccountHistory", "stage", "^IndexAccountHistory$"),
  "stage", "12-Prune", "stage", "^Prune$"),
  "stage", "13-Finish", "stage", "^Finish$")
EOT
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
              displayName = "entities/s"
            }
          ]
        }
      }
    }
  ]

  # ---------------------------------------------------------------------------
  # V1 Row 4: All Stages - ETA (hours)
  # ---------------------------------------------------------------------------
  v1_eta_tiles = [
    {
      xPos   = 0
      yPos   = 64
      width  = 48
      height = 24
      widget = {
        title = "All Stages: ETA (hours)"
        timeSeriesTable = {
          dataSets = [
            {
              timeSeriesQuery = {
                # NOTE: label_replace must be applied AFTER rate() in Cloud Monitoring
                # ETA = (entities_total - entities_processed) / rate(entities_processed) / 3600
                prometheusQuery = <<-EOT
(
  label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(
    reth_sync_entities_total{vm_name=~"op-reth.*|c4-.*"},
    "stage", "01-Headers", "stage", "^Headers$"),
    "stage", "02-Bodies", "stage", "^Bodies$"),
    "stage", "03-SenderRecovery", "stage", "^SenderRecovery$"),
    "stage", "04-Execution", "stage", "^Execution$"),
    "stage", "05-MerkleUnwind", "stage", "^MerkleUnwind$"),
    "stage", "06-AccountHashing", "stage", "^AccountHashing$"),
    "stage", "07-StorageHashing", "stage", "^StorageHashing$"),
    "stage", "08-MerkleExecute", "stage", "^MerkleExecute$"),
    "stage", "09-TransactionLookup", "stage", "^TransactionLookup$"),
    "stage", "10-IndexStorageHistory", "stage", "^IndexStorageHistory$"),
    "stage", "11-IndexAccountHistory", "stage", "^IndexAccountHistory$"),
    "stage", "12-Prune", "stage", "^Prune$"),
    "stage", "13-Finish", "stage", "^Finish$")
  -
  label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(
    reth_sync_entities_processed{vm_name=~"op-reth.*|c4-.*"},
    "stage", "01-Headers", "stage", "^Headers$"),
    "stage", "02-Bodies", "stage", "^Bodies$"),
    "stage", "03-SenderRecovery", "stage", "^SenderRecovery$"),
    "stage", "04-Execution", "stage", "^Execution$"),
    "stage", "05-MerkleUnwind", "stage", "^MerkleUnwind$"),
    "stage", "06-AccountHashing", "stage", "^AccountHashing$"),
    "stage", "07-StorageHashing", "stage", "^StorageHashing$"),
    "stage", "08-MerkleExecute", "stage", "^MerkleExecute$"),
    "stage", "09-TransactionLookup", "stage", "^TransactionLookup$"),
    "stage", "10-IndexStorageHistory", "stage", "^IndexStorageHistory$"),
    "stage", "11-IndexAccountHistory", "stage", "^IndexAccountHistory$"),
    "stage", "12-Prune", "stage", "^Prune$"),
    "stage", "13-Finish", "stage", "^Finish$")
)
/ clamp_min(
  label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(
    rate(reth_sync_entities_processed{vm_name=~"op-reth.*|c4-.*"}[5m]),
    "stage", "01-Headers", "stage", "^Headers$"),
    "stage", "02-Bodies", "stage", "^Bodies$"),
    "stage", "03-SenderRecovery", "stage", "^SenderRecovery$"),
    "stage", "04-Execution", "stage", "^Execution$"),
    "stage", "05-MerkleUnwind", "stage", "^MerkleUnwind$"),
    "stage", "06-AccountHashing", "stage", "^AccountHashing$"),
    "stage", "07-StorageHashing", "stage", "^StorageHashing$"),
    "stage", "08-MerkleExecute", "stage", "^MerkleExecute$"),
    "stage", "09-TransactionLookup", "stage", "^TransactionLookup$"),
    "stage", "10-IndexStorageHistory", "stage", "^IndexStorageHistory$"),
    "stage", "11-IndexAccountHistory", "stage", "^IndexAccountHistory$"),
    "stage", "12-Prune", "stage", "^Prune$"),
    "stage", "13-Finish", "stage", "^Finish$")
, 0.0001)
/ 3600
EOT
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
              displayName = "ETA (hours)"
            }
          ]
        }
      }
    }
  ]

  # ---------------------------------------------------------------------------
  # V1 Row 5: All Stages - Checkpoint (block #)
  # ---------------------------------------------------------------------------
  v1_checkpoint_tiles = [
    {
      xPos   = 0
      yPos   = 88
      width  = 48
      height = 20
      widget = {
        title = "All Stages: Checkpoint (block #)"
        timeSeriesTable = {
          dataSets = [
            {
              timeSeriesQuery = {
                prometheusQuery = <<-EOT
label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(
  reth_sync_checkpoint{vm_name=~"op-reth.*|c4-.*"},
  "stage", "01-Headers", "stage", "^Headers$"),
  "stage", "02-Bodies", "stage", "^Bodies$"),
  "stage", "03-SenderRecovery", "stage", "^SenderRecovery$"),
  "stage", "04-Execution", "stage", "^Execution$"),
  "stage", "05-MerkleUnwind", "stage", "^MerkleUnwind$"),
  "stage", "06-AccountHashing", "stage", "^AccountHashing$"),
  "stage", "07-StorageHashing", "stage", "^StorageHashing$"),
  "stage", "08-MerkleExecute", "stage", "^MerkleExecute$"),
  "stage", "09-TransactionLookup", "stage", "^TransactionLookup$"),
  "stage", "10-IndexStorageHistory", "stage", "^IndexStorageHistory$"),
  "stage", "11-IndexAccountHistory", "stage", "^IndexAccountHistory$"),
  "stage", "12-Prune", "stage", "^Prune$"),
  "stage", "13-Finish", "stage", "^Finish$")
EOT
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
              displayName = "Block #"
            }
          ]
        }
      }
    }
  ]

  # ---------------------------------------------------------------------------
  # V1 Row 6: Progress Chart (Progress % over time)
  # ---------------------------------------------------------------------------
  # Line chart showing progress percentage over time per VM/stage.
  # Useful for visualizing sync progress and identifying slowdowns.
  # ---------------------------------------------------------------------------
  v1_progress_chart_tiles = [
    {
      xPos   = 0
      yPos   = 108
      width  = 48
      height = 16
      widget = {
        title = "Progress % Over Time"
        xyChart = {
          dataSets = [{
            timeSeriesQuery = {
              prometheusQuery = <<-EOT
label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(
  reth_sync_entities_processed{vm_name=~"op-reth.*|c4-.*"},
  "stage", "01-Headers", "stage", "^Headers$"),
  "stage", "02-Bodies", "stage", "^Bodies$"),
  "stage", "03-SenderRecovery", "stage", "^SenderRecovery$"),
  "stage", "04-Execution", "stage", "^Execution$"),
  "stage", "05-MerkleUnwind", "stage", "^MerkleUnwind$"),
  "stage", "06-AccountHashing", "stage", "^AccountHashing$"),
  "stage", "07-StorageHashing", "stage", "^StorageHashing$"),
  "stage", "08-MerkleExecute", "stage", "^MerkleExecute$"),
  "stage", "09-TransactionLookup", "stage", "^TransactionLookup$"),
  "stage", "10-IndexStorageHistory", "stage", "^IndexStorageHistory$"),
  "stage", "11-IndexAccountHistory", "stage", "^IndexAccountHistory$"),
  "stage", "12-Prune", "stage", "^Prune$"),
  "stage", "13-Finish", "stage", "^Finish$")
/
label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(
  reth_sync_entities_total{vm_name=~"op-reth.*|c4-.*"},
  "stage", "01-Headers", "stage", "^Headers$"),
  "stage", "02-Bodies", "stage", "^Bodies$"),
  "stage", "03-SenderRecovery", "stage", "^SenderRecovery$"),
  "stage", "04-Execution", "stage", "^Execution$"),
  "stage", "05-MerkleUnwind", "stage", "^MerkleUnwind$"),
  "stage", "06-AccountHashing", "stage", "^AccountHashing$"),
  "stage", "07-StorageHashing", "stage", "^StorageHashing$"),
  "stage", "08-MerkleExecute", "stage", "^MerkleExecute$"),
  "stage", "09-TransactionLookup", "stage", "^TransactionLookup$"),
  "stage", "10-IndexStorageHistory", "stage", "^IndexStorageHistory$"),
  "stage", "11-IndexAccountHistory", "stage", "^IndexAccountHistory$"),
  "stage", "12-Prune", "stage", "^Prune$"),
  "stage", "13-Finish", "stage", "^Finish$")
* 100
EOT
            }
            plotType       = "LINE"
            legendTemplate = "{{vm_name}} - {{stage}}"
          }]
          yAxis = {
            label = "Progress %"
          }
        }
      }
    }
  ]
}

# -----------------------------------------------------------------------------
# Dashboard V1 - Entity-Based Sync Status
# -----------------------------------------------------------------------------
# Layout:
#   Row 1: Active Stages (entities/s > 0)     - yPos=0,   height=16
#   Row 2: All Stages - Progress %            - yPos=16,  height=24
#   Row 3: All Stages - Throughput (entities) - yPos=40,  height=24
#   Row 4: All Stages - ETA (hours)           - yPos=64,  height=24
#   Row 5: All Stages - Checkpoint            - yPos=88,  height=20
#   Row 6: Progress Chart                     - yPos=108, height=16
#
# Uses reth_sync_entities_processed for accurate mid-batch progress tracking.
# Entity type varies by stage (stage column indicates what's being processed).
# -----------------------------------------------------------------------------
resource "google_monitoring_dashboard" "reth_benchmark_v1" {
  dashboard_json = jsonencode({
    displayName = "op-reth Benchmark v1"

    mosaicLayout = {
      columns = 48
      tiles = concat(
        local.v1_active_stages_tiles,
        local.v1_progress_pct_tiles,
        local.v1_throughput_tiles,
        local.v1_eta_tiles,
        local.v1_checkpoint_tiles,
        local.v1_progress_chart_tiles
      )
    }
  })

  depends_on = [google_project_service.telemetry]
}

# =============================================================================
# V3 Dashboard - Per-Stage Breakdown (13 stages, each with Throughput/Checkpoint/ETA)
# =============================================================================
#
# Layout:
#   Row 1:  yPos=0,   height=8  - Scorecards: L2 Tip, Chain Growth (Min/Avg/Max)
#   Row 2:  yPos=8,   height=20 - 01-Headers
#   Row 3:  yPos=28,  height=20 - 02-Bodies
#   Row 4:  yPos=48,  height=20 - 03-SenderRecovery
#   Row 5:  yPos=68,  height=20 - 04-Execution
#   Row 6:  yPos=88,  height=20 - 05-MerkleUnwind
#   Row 7:  yPos=108, height=20 - 06-AccountHashing
#   Row 8:  yPos=128, height=20 - 07-StorageHashing
#   Row 9:  yPos=148, height=20 - 08-MerkleExecute
#   Row 10: yPos=168, height=20 - 09-TransactionLookup
#   Row 11: yPos=188, height=20 - 10-IndexStorageHistory
#   Row 12: yPos=208, height=20 - 11-IndexAccountHistory
#   Row 13: yPos=228, height=20 - 12-Prune
#   Row 14: yPos=248, height=20 - 13-Finish
#
# Each stage row has 3 tables: Throughput (xPos=0), Checkpoint (xPos=16), ETA (xPos=32)
# -----------------------------------------------------------------------------

locals {
  # VM filter pattern for v3 dashboard
  v3_vm_filter = "vm_name=~\"op-reth.*|c4-.*\""

  # Row 1: Chain Overview Scorecards (same as overview dashboard)
  v3_scorecard_tiles = [
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

  # Stage definitions for v3 dashboard
  # Each stage gets a row with Throughput, Checkpoint, and ETA tables
  # 
  # Metric strategy per stage:
  #   - Most stages: rate(reth_sync_checkpoint) for throughput
  #   - MerkleExecute: Use stage_progress distribution metric for real-time progress
  #   - StorageHashing: Shows 0 during batch (no real-time metric available)
  v3_stages = [
    { num = "01", name = "Headers", throughput_type = "checkpoint" },
    { num = "02", name = "Bodies", throughput_type = "checkpoint" },
    { num = "03", name = "SenderRecovery", throughput_type = "checkpoint" },
    { num = "04", name = "Execution", throughput_type = "entities" },
    { num = "05", name = "MerkleUnwind", throughput_type = "checkpoint" },
    { num = "06", name = "AccountHashing", throughput_type = "entities" },
    { num = "07", name = "StorageHashing", throughput_type = "checkpoint" },
    { num = "08", name = "MerkleExecute", throughput_type = "progress" },
    { num = "09", name = "TransactionLookup", throughput_type = "checkpoint" },
    { num = "10", name = "IndexStorageHistory", throughput_type = "checkpoint" },
    { num = "11", name = "IndexAccountHistory", throughput_type = "checkpoint" },
    { num = "12", name = "Prune", throughput_type = "checkpoint" },
    { num = "13", name = "Finish", throughput_type = "checkpoint" },
  ]

  # Generate tiles for each stage (3 widgets per stage: Throughput, Checkpoint, ETA)
  # Row 1 is scorecards at yPos=0 height=8, stages start at yPos=8
  v3_stage_tiles = flatten([
    for idx, stage in local.v3_stages : [
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
                    ? "logging_googleapis_com:user:reth_stage_progress_distribution_sum{stage=\"${stage.name}\", ${local.v3_vm_filter}} / logging_googleapis_com:user:reth_stage_progress_distribution_count{stage=\"${stage.name}\", ${local.v3_vm_filter}}"
                    : stage.throughput_type == "entities"
                    ? "rate(reth_sync_entities_processed{stage=\"${stage.name}\", ${local.v3_vm_filter}}[5m])"
                    : "rate(reth_sync_checkpoint{stage=\"${stage.name}\", ${local.v3_vm_filter}}[5m])"
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
                  prometheusQuery = "reth_sync_checkpoint{stage=\"${stage.name}\", ${local.v3_vm_filter}}"
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
        yPos   = 8 + (idx * 20)
        width  = 16
        height = 20
        widget = {
          title = "${stage.num}-${stage.name}: ETA (hours)"
          timeSeriesTable = {
            dataSets = [
              {
                timeSeriesQuery = {
                  # ETA = blocks_remaining / (blocks_per_second * 3600)
                  # Uses on(vm_name) to match labels between op_node and reth metrics
                  prometheusQuery = "(op_node_default_refs_number{layer=\"l2\",type=\"l2_unsafe\"} - on(vm_name) reth_sync_checkpoint{stage=\"${stage.name}\", ${local.v3_vm_filter}}) / on(vm_name) (rate(reth_sync_checkpoint{stage=\"${stage.name}\", ${local.v3_vm_filter}}[15m]) * 3600)"
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
# V3 Dashboard Resource
# -----------------------------------------------------------------------------
resource "google_monitoring_dashboard" "reth_benchmark_v3" {
  dashboard_json = jsonencode({
    displayName = "op-reth Benchmark v3 (Per-Stage)"

    mosaicLayout = {
      columns = 48
      tiles = concat(
        local.v3_scorecard_tiles,
        local.v3_stage_tiles
      )
    }
  })

  depends_on = [google_project_service.telemetry]
}
