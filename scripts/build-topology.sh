#!/bin/bash
# build-topology.sh
# Builds the INWK6312 Lab 1 routed namespace topology:
# ns-hostA -- ns-router -- ns-hostB

set -e

NAMESPACES=("ns-router" "ns-hostA" "ns-hostB" "ns-hostC")

echo Add namespaces if they do not exist
for ns in "${NAMESPACES[@]}"; do
    if ip netns list | grep -q "$ns"; then
        echo "$ns already exists, skipping"
    else
        ip netns add "$ns"
        echo "Created $ns"
    fi
done

echo Create the veth pairs and move each end into the right namespace
sudo ip link add veth-r1 type veth peer name veth-a
sudo ip link set veth-r1 netns ns-router
sudo ip link set veth-a netns ns-hostA

sudo ip link add veth-r2 type veth peer name veth-b
sudo ip link set veth-r2 netns ns-router
sudo ip link set veth-b netns ns-hostB

sudo ip link add veth-r3 type veth peer name veth-c
sudo ip link set veth-r3 netns ns-router
sudo ip link set veth-c netns ns-hostC

echo Assign addresses to each interface
sudo ip netns exec ns-router ip addr add 10.10.21.1/24 dev veth-r1
sudo ip netns exec ns-router ip addr add 10.10.2.1/24 dev veth-r2
sudo ip netns exec ns-router ip addr add 10.10.3.1/24 dev veth-r3

sudo ip netns exec ns-hostA ip addr add 10.10.21.2/24 dev veth-a
sudo ip netns exec ns-hostB ip addr add 10.10.2.2/24 dev veth-b
sudo ip netns exec ns-hostC ip addr add 10.10.3.2/24 dev veth-c

echo Bring up every interface and every loopback
for ns in "${NAMESPACES[@]}"; do
    sudo ip netns exec $ns ip link set lo up
done
sudo ip netns exec ns-router ip link set veth-r1 up
sudo ip netns exec ns-router ip link set veth-r2 up
sudo ip netns exec ns-router ip link set veth-r3 up
sudo ip netns exec ns-hostA ip link set veth-a up
sudo ip netns exec ns-hostB ip link set veth-b up
sudo ip netns exec ns-hostC ip link set veth-c up

echo Enable IP forwarding on ns-router
sudo ip netns exec ns-router sysctl -w net.ipv4.ip_forward=1

echo Add the static routes on ns-hostA and ns-hostB
sudo ip netns exec ns-hostA ip route add default via 10.10.21.1
sudo ip netns exec ns-hostB ip route add default via 10.10.2.1
sudo ip netns exec ns-hostC ip route add default via 10.10.3.1

echo "Topology build complete"
