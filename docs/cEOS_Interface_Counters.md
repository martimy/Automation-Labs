## Problem

While generating traffic between the two hosts in the topology, I noticed that the interface counters on the cEOS nodes do not updated and gNMI telemetry return the same data in every sample.


I found this explanation:


This behavior stems from how **cEOS-lab** handles hardware abstraction (specifically `Kernel / SysFS` polling vs. hardware ASIC polling) and how interface links are constructed under Containerlab using Linux `veth` pairs.


## Root Cause

1. **Agent / Polling Model**: Physical Arista switches read statistics directly from switch chip ASICs via SDK drivers. In cEOS, hardware ASICs do not exist; interfaces rely on the Linux kernel netdev drivers (`veth` pairs inserted by Containerlab).
2. **`eth` vs. `Ma0` Interface Accounting**:
* **`Management0` / `Ma0**` is directly bound to the container's standard network namespace interface (`eth0` on the Linux host/docker network), which normal Linux kernel socket drivers update continuously.
* **Data-plane interfaces (`Ethernet1`, `Ethernet2`, etc.)** rely on Arista's kernel drivers (such as `EtDriver` or system agents like `EthIntf`). Depending on the cEOS image version, kernel capability flags, or interface mapping settings, the internal polling daemon may fail to pull interface metrics directly from the host's SysFS `/sys/class/net/ethX/statistics/` paths into the EOS SysDB.


### Common Workarounds & Fixes

#### 1. Enable Hardware Emulation / Agent Environment Variables

Add environment variables to your topology file under `env:` or `kinds.arista_ceos.env` to ensure cEOS routes kernel netdev interface stats into SysDB.

```yaml
topology:
  kinds:
    arista_ceos:
      env:
        INTFTYPE: "eth"
        ETBA: "1"

```

#### 2. Verify SysFS Counter Access (`/proc` and `/sys` mounts)

Some cEOS versions require access to the host's `/proc` or system interface counters. Ensure Containerlab is not mounting `/sys` in read-only mode or restricting capability flags required by `EthIntf`. In `clab`, adding privileges to cEOS nodes can resolve driver polling permission failures:

```yaml
topology:
  nodes:
    ceos1:
      kind: arista_ceos
      image: ceos:4.32.0F
      exec:
        - ip link set eth1 promisc on

```

#### 3. Software/Image Version Behavior

* **cEOS 4.28.0M and newer**: cEOS transitioned to full support for Linux `cgroups v2` and updated netdev polling. If running an older release (e.g., `< 4.26`), data-plane counters often remain static at zero due to missing veth driver support inside the Arista `EtDriver` agent. Upgrading to a modern cEOS-lab release (e.g., `4.30+` or `4.32+`) typically resolves silent counter stalls.

#### 4. Interface Mapping Override

When mapping `eth1` to `Ethernet1`, ensure Containerlab's generated or custom `interface_mapping.json` correctly registers the `ethX` system device. If EOS does not properly recognize the mapped underlying veth name, control plane packets will pass, but the `EthIntf` agent won't bind the kernel interface statistics counter.

---

### Quick Verification via CLI

Inside the cEOS CLI, compare the Kernel-level interface counters against SysDB:

```text
# Check Kernel Netdev Counters (Should increment)
bash
cat /proc/net/dev

# Check EOS Interface Counters (If 0, EthIntf is not sync'd with netdev)
show interfaces Ethernet1 | grep "input packets"

```

If `/proc/net/dev` shows increasing packets but `show interfaces Ethernet1` stays at zero, upgrading the cEOS image or explicitly adding `INTFTYPE: "eth"` in your `.clab.yml` topology is the recommended solution.

## For v4.36

In **cEOS-lab 4.36**, this behavior is tied to structural architectural changes introduced in recent Arista cEOS releases regarding system agent polling and container network namespace interface bindings.

When running 4.36 under Containerlab, control plane traffic passes through Linux `veth` interfaces seamlessly, but the internal hardware abstraction layer (`EthIntf` / SysDB daemons) fails to bind to the `veth` interface statistics drivers automatically.

### Root Causes in cEOS 4.36

1. **Kernel Driver Polling (`ETBA` / `INTFTYPE`)**: Starting around the 4.32+ and 4.35+ release series, cEOS relies on explicitly declared interface types for non-ASIC kernel environments (`veth` vs native `eth`). If these aren't set, `EthIntf` ignores SysFS `/sys/class/net/ethX/statistics` counters for data-plane interfaces (`Ethernet1+`) while continuing to update `Management1` (`eth0`) via default Linux socket drivers.
2. **Missing Container Capabilities (`NET_ADMIN` / `SYS_ADMIN`)**: In 4.36, cEOS requires direct hardware-like access to system socket parameters and raw netlink sockets to sync `/proc/net/dev` with EOS `SysDB`. If Containerlab runs the node with restricted container privileges, packet counters fail to populate in `show interfaces`.


### Recommended Fixes

#### Fix 1: Add Hardware Environment Variables (Most Common)

In your `.clab.yml` topology file, pass the `INTFTYPE` and `ETBA` environment variables to force cEOS to pull counters directly from the underlying Linux `eth` netdev drivers:

```yaml
topology:
  kinds:
    arista_ceos:
      env:
        INTFTYPE: "eth"
        ETBA: "1"

```

If you prefer applying this per node rather than globally under `kinds`:

```yaml
topology:
  nodes:
    ceos1:
      kind: arista_ceos
      image: ceos:4.36.0F # or 4.36.1F
      env:
        INTFTYPE: "eth"
        ETBA: "1"

```

---

#### Fix 2: Grant Extended Container Privileges

If environment variables alone do not restore counters, ensure Containerlab gives the cEOS container elevated privileges to inspect kernel statistics interfaces:

```yaml
topology:
  nodes:
    ceos1:
      kind: arista_ceos
      image: ceos:4.36.0F
      stage: create
      sysctls:
        net.ipv4.ip_forward: 1
      # Grant full capability or run privileged if required
      exec:
        - ip link set eth1 promisc on

```

---

### How to Verify the Fix

1. Deploy or re-deploy the lab:
```bash
containerlab deploy -t your-topo.clab.yml --reconfigure

```


2. Generate data-plane traffic across two cEOS interfaces (e.g., ping between loopbacks or adjacent interfaces).
3. Check if the Linux host sees the counters vs EOS SysDB:
**Linux Netdev (Host Level):**
```bash
docker exec -it ceos1 bash -c "cat /proc/net/dev"

```


*You should see packet counts for `eth1`, `eth2`, etc., incrementing.*
**EOS CLI Level:**
```bash
docker exec -it clab-<labname>-ceos1 Cli -c "show interfaces Ethernet1 | grep 'packets input'"

```


*With `INTFTYPE: "eth"` set, the EOS CLI output will now mirror the `/proc/net/dev` counts.*



#### Using gNMI

```bash
gnmic -a ceos1:6030 -u admin -p admin --insecure   subscribe --path /openconfig-interfaces:interfaces/interface[name=Ethernet3]/state/counters/out-octets  --stream-mode sample --sample-interval 10s

```

```bash
docker exec ceos2 Cli -c "traceroute 10.0.100.2"
traceroute to 10.0.100.2 (10.0.100.2), 30 hops max, 60 byte packets
 1  10.0.12.1 (10.0.12.1)  0.088 ms  0.051 ms  0.035 ms
 2  10.0.100.2 (10.0.100.2)  1.259 ms  0.689 ms  0.649 ms
```


#### Overvations

even w/o any modifications, this updates counters with gNMI:

```
docker exec ceos2  ping 10.0.100.2
```

### Conclusion

this behavior is unpredictable. I need more investigation.
