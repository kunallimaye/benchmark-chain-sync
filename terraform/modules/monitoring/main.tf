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
#   {__name__="logging.googleapis.com/user/reth_stage_log_count", vm_name=~"op-reth.*", stage_eta!=""}
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
                prometheusQuery = <<-EOT
rate(
  label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(
    reth_sync_entities_processed{vm_name=~"op-reth.*"},
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
[5m]) > 0
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
  reth_sync_entities_processed{vm_name=~"op-reth.*"},
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
  reth_sync_entities_total{vm_name=~"op-reth.*"},
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
                prometheusQuery = <<-EOT
rate(
  label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(
    reth_sync_entities_processed{vm_name=~"op-reth.*"},
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
[5m])
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
                prometheusQuery = <<-EOT
(
  label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(
    reth_sync_entities_total{vm_name=~"op-reth.*"},
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
    reth_sync_entities_processed{vm_name=~"op-reth.*"},
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
  rate(
    label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(label_replace(
      reth_sync_entities_processed{vm_name=~"op-reth.*"},
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
  [5m]), 0.0001)
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
  reth_sync_checkpoint{vm_name=~"op-reth.*"},
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
  reth_sync_entities_processed{vm_name=~"op-reth.*"},
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
  reth_sync_entities_total{vm_name=~"op-reth.*"},
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
