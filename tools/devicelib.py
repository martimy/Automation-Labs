#!/usr/bin/env python3
"""Shared device configuration loading for NETCONF and gNMI CLI tools."""
import sys
import os
import yaml

# Default path to the shared device configuration file; can be overridden
# with the DEVICES_FILE environment variable.
DEFAULT_CONFIG_FILE = os.environ.get("DEVICES_FILE", "devices.yaml")


def load_devices(protocol, config_file=DEFAULT_CONFIG_FILE):
    """Loads device connection parameters for a given protocol ('netconf' or
    'gnmi') from a shared YAML file.

    Returns a dict mapping device name -> connection params dict, containing
    only devices that have a section for the requested protocol.
    """
    try:
        with open(config_file, "r") as f:
            data = yaml.safe_load(f) or {}
    except FileNotFoundError:
        print(f"Error: Device config file '{config_file}' not found.")
        sys.exit(1)
    except yaml.YAMLError as e:
        print(f"Error: Failed to parse '{config_file}': {e}")
        sys.exit(1)

    all_devices = data.get("devices")
    if not all_devices:
        print(f"Error: No 'devices' section found in '{config_file}'.")
        sys.exit(1)

    devices = {}
    for name, entry in all_devices.items():
        params = entry.get(protocol)
        if not params:
            continue
        params = dict(params)  # avoid mutating the parsed data in place
        if protocol == "gnmi":
            # pygnmi expects 'target' as a tuple (host, port); YAML gives a list.
            target = params.get("target")
            if isinstance(target, list):
                params["target"] = tuple(target)
        devices[name] = params

    if not devices:
        print(f"Error: No devices with a '{protocol}' section found in '{config_file}'.")
        sys.exit(1)

    return devices
