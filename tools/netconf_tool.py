#!/usr/bin/env python3
import sys
from devicelib import DEFAULT_CONFIG_FILE, load_devices
from ncclient import manager
from urllib.parse import urlparse, parse_qs

def get_capabilities(m):
    """Prints the capabilities supported by the device."""
    caps = [c for c in m.server_capabilities if "capability:" in c]
    for cap in sorted(caps):
        print(cap)

def get_modules(m, max_extras_len=80):
    """Prints the YANG modules supported by the device in a nice, aligned format."""
    mods = [c for c in m.server_capabilities if "module=" in c]

    parsed = []
    for cap in mods:
        query = parse_qs(urlparse(cap).query)
        name = query.get("module", [""])[0]
        revision = query.get("revision", [""])[0]
        extras = []
        if "deviations" in query:
            extras.append(f"deviations={query['deviations'][0]}")
        if "features" in query:
            extras.append(f"features={query['features'][0]}")
        parsed.append((name, revision, ", ".join(extras)))

    parsed.sort(key=lambda x: x[0])

    name_width = max((len(p[0]) for p in parsed), default=0)
    rev_width = max((len(p[1]) for p in parsed), default=0)

    for name, revision, extras in parsed:
        if len(extras) > max_extras_len:
            extras = extras[:max_extras_len - 3] + "..."
        line = f"{name:<{name_width}}  rev={revision:<{rev_width}}"
        if extras:
            line += f"  [{extras}]"
        print(line)
                
def get_config(m, filter_xml):
    """Retrieves and prints the network-instance configuration."""
    config = m.get_config(source="running", filter=("subtree", filter_xml))
    print(config.data_xml)


def save_schema(m, schema_name):
    """Downloads a YANG schema and saves it to a file."""
    try:
        schema = m.get_schema(schema_name)
        filename = f"{schema_name}.yang"
        with open(filename, "w") as f:
            f.write(schema.data)
        print(f"Schema saved to {filename}")
    except Exception as e:
        print(e)


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <device> <action> [xml-filter | schema-name]")
        print(f"       (device config read from {DEFAULT_CONFIG_FILE},"
              f" override with DEVICES_FILE)")
        print("Actions: capabilities, modules, config, schema")
        sys.exit(1)

    devices = load_devices("netconf")

    device_name = sys.argv[1]
    action = sys.argv[2]

    if device_name not in devices:
        print(f"Error: Unknown device '{device_name}'. Available: {', '.join(devices.keys())}")
        sys.exit(1)

    conn_params = devices[device_name]

    # Connect to the device and perform the action
    with manager.connect(**conn_params) as m:
        if action == "capabilities":
            get_capabilities(m)
        elif action == "modules":
            get_modules(m)
        elif action == "config":
            if len(sys.argv) < 4:
                print("Error: Action 'config' requires a xml-filter.")
                print(f"Usage: {sys.argv[0]} {device_name} config <xml-filter>")
                sys.exit(1)
            get_config(m, sys.argv[3])
        elif action == "schema":
            if len(sys.argv) < 4:
                print("Error: Action 'schema' requires a schema name.")
                print(f"Usage: {sys.argv[0]} {device_name} schema <schema-name>")
                sys.exit(1)
            save_schema(m, sys.argv[3])
        else:
            print(f"Error: Unknown action '{action}'.")


if __name__ == "__main__":
    main()
