# =============================================================================
# Benchmark Module Outputs
# =============================================================================

output "vms" {
  description = "Map of VM names to their details"
  value = {
    for name, vm in module.vm : name => {
      vm_name              = vm.vm_name
      external_ip          = vm.external_ip
      internal_ip          = vm.internal_ip
      zone                 = vm.zone
      machine_type         = vm.machine_type
      storage_type         = vm.storage_type
      reth_version         = vm.reth_version
      confidential_compute = vm.confidential_compute
      has_builtin_lssd     = vm.has_builtin_lssd
      disk_name            = vm.disk_name
    }
  }
}

output "vm_names" {
  description = "List of VM names"
  value       = [for name, vm in module.vm : vm.vm_name]
}

output "builtin_lssd_vms" {
  description = "List of VM names with built-in local SSD (require rsync for data)"
  value       = [for name, vm in module.vm : vm.vm_name if vm.has_builtin_lssd]
}

output "persistent_disk_vms" {
  description = "List of VM names with persistent disks (data from snapshot)"
  value       = [for name, vm in module.vm : vm.vm_name if !vm.has_builtin_lssd]
}
