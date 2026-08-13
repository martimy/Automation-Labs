#!/bin/bash
# teardown-topology.sh

NAMESPACES=("ns-router" "ns-routerA" "ns-hostB" "ns-routerC")

for ns in "${NAMESPACES[@]}"; do
    if ip netns list | grep -q "$ns"; then
        ip netns del "$ns"
        echo "Deleted $ns"
    else
        echo "$ns does not exist, skipping"
    fi
done
