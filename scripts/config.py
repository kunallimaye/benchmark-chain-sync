#!/usr/bin/env python3
"""
Parse config.toml and output values for shell scripts.

Usage:
    ./scripts/config.py                     # Output full config as JSON
    ./scripts/config.py project.project_id  # Get specific value
    ./scripts/config.py project             # Get section as JSON
    ./scripts/config.py vm                  # Get VM list as JSON
    ./scripts/config.py vm.0.name           # Get first VM's name

Examples:
    PROJECT_ID=$(./scripts/config.py project.project_id)
    ZONE=$(./scripts/config.py project.zone)
    VM_COUNT=$(./scripts/config.py vm | jq length)
"""
import tomllib
import sys
import json
from pathlib import Path


def get_config_path():
    """Find config.toml relative to this script or cwd."""
    # Try relative to script location first
    script_dir = Path(__file__).parent.parent
    config_path = script_dir / "config.toml"
    if config_path.exists():
        return config_path
    # Fall back to cwd
    return Path("config.toml")


def get_nested_value(data, path):
    """Get a nested value from dict/list using dot notation."""
    keys = path.split(".")
    value = data
    for key in keys:
        if isinstance(value, list):
            try:
                index = int(key)
                value = value[index]
            except (ValueError, IndexError):
                return None
        elif isinstance(value, dict):
            value = value.get(key)
            if value is None:
                return None
        else:
            return None
    return value


def merge_vm_defaults(config):
    """Merge [defaults.vm] into each [[vm]] entry."""
    defaults = config.get("defaults", {}).get("vm", {})
    vms = config.get("vm", [])
    
    for vm in vms:
        machine_type = vm.get("machine_type", defaults.get("machine_type", ""))
        is_lssd = machine_type.endswith("-lssd")
        
        for key, value in defaults.items():
            if key not in vm:
                # Don't apply storage_type or disk_size_gb for LSSD machines
                if is_lssd and key in ("storage_type", "disk_size_gb"):
                    continue
                vm[key] = value
    
    return config


def main():
    config_path = get_config_path()
    
    if not config_path.exists():
        print(f"ERROR: config.toml not found at {config_path}", file=sys.stderr)
        sys.exit(1)
    
    with open(config_path, "rb") as f:
        config = tomllib.load(f)
    
    # Merge defaults into VMs
    config = merge_vm_defaults(config)
    
    if len(sys.argv) < 2:
        # Output full config as JSON
        print(json.dumps(config, indent=2))
        return
    
    path = sys.argv[1]
    value = get_nested_value(config, path)
    
    if value is None:
        # Return empty string for missing values (shell-friendly)
        print("")
    elif isinstance(value, (dict, list)):
        print(json.dumps(value))
    elif isinstance(value, bool):
        # Shell-friendly boolean
        print("true" if value else "false")
    else:
        print(value)


if __name__ == "__main__":
    main()
