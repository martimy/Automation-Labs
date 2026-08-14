#!/usr/bin/env python3
import sys
import json
from pygnmi.client import gNMIclient
from devicelib import load_devices, DEFAULT_CONFIG_FILE

def get_modules(gc):
    """Prints the YANG modules supported by the device in a nice, aligned format."""
    mods = [
        (c["name"].split(":")[-1], c["organization"], c["version"])
        for c in gc.capabilities()["supported_models"]
    ]
    mods.sort(key=lambda x: x[0])

    name_width = max((len(name) for name, _, _ in mods), default=0)
    org_width = max((len(org) for _, org, _ in mods), default=0)

    for name, org, version in mods:
        print(f"{name:<{name_width}}  {org:<{org_width}}  {version}")
        
def get_config(gc, path):
    """Retrieves and prints configuration."""
    result = gc.get(path=[path], datatype="config")
    # path should be a list
    # Using json.dumps for pretty printing the result
    print(json.dumps(result, indent=2))


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <device> <action> [path]")
        print(f"       (device config read from {DEFAULT_CONFIG_FILE},"
              f" override with DEVICES_FILE)")
        print("Actions: modules, config")
        sys.exit(1)

    devices = load_devices("gnmi")

    device_name = sys.argv[1]
    action = sys.argv[2]

    if device_name not in devices:
        print(f"Error: Unknown device '{device_name}'. Available: {', '.join(devices.keys())}")
        sys.exit(1)

    conn_params = devices[device_name]

    # Connect to the device and perform the action
    with gNMIclient(**conn_params) as gc:
        if action == "modules":
            get_modules(gc)
        elif action == "config":
            if len(sys.argv) < 4:
                print("Error: Action 'config' requires a path.")
                print(f"Usage: {sys.argv[0]} {device_name} config <path>")
                sys.exit(1)
            get_config(gc, sys.argv[3])
        else:
            print(f"Error: Unknown action '{action}'.")


if __name__ == "__main__":
    main()
