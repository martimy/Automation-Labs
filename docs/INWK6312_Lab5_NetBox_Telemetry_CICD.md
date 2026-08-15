---
title: INWK6312 - Lab 5
subtitle: Source of Truth, Real Traffic Telemetry, and a CI/CD Pipeline
highlight-style: tango
toc: true
fontsize: 11pt
numbersections: false
colorlinks: true
listings: true
documentclass: article
output:
    pdf_document:
        toc_depth: 2
        highlight: custom-tango.theme # option: tango, pygments, kate, monochrome, espresso, haddock, breezedark
geometry: margin=1in

header-includes: |
  \usepackage{fvextra}
  \DefineVerbatimEnvironment{Highlighting}{Verbatim}{breaklines,commandchars=\\\{\}}
  \usepackage{fancyhdr}
  \usepackage{lastpage}
  \pagestyle{fancy}
  \fancyhf{}
  
  \lhead{\title}
  \renewcommand{\headrulewidth}{0.5pt}

  \lfoot{v1.0}
  \cfoot{\copyright\ 2026 INWK6312}
  \rfoot{Page \thepage\ of \pageref{LastPage}}
  \renewcommand{\headrulewidth}{0.5pt}

  \usepackage{tcolorbox}
  \newtcolorbox{myquote}{colback=purple!5!white, colframe=purple!75!black, arc=0mm}
  \renewenvironment{quote}{\begin{myquote}}{\end{myquote}}
---

\newpage


# Introduction

This labs covers several topics, including NetBox as a source of truth, receiving telemetry, implementing a CI/CD pipeline, and verification with both Ansible and Batfish.

You will deploy a NetBox instance and populate it with a script. You will extend the network topology used throughout all labs with two hosts to generate traffic through the network and watch it via gNMI. You will also build a small CI/CD pipeline utilizing Ansible and Batfish for doing configuration state verification wrapped in a GitHub Actions workflow that runs automatically when you push.

# Lab Objectives

By the end of this lab, you will be able to:

1. Deploy NetBox and populate it programmatically using its Python SDK, rather than through the web interface
2. Query the same data through both a REST and a GraphQL API and compare the two
3. Extend an existing Containerlab topology with new nodes and reconfigure it without losing what was already there
4. Use Ansible to pull configuration data from an external source of truth instead of a hardcoded template variable
5. Generate real network traffic with iperf3 and observe it with a gNMI Subscribe script adapted from a previous lab
6. Write Ansible based verification tasks, register and assert, against live configuration state
7. Write a narrow Batfish check against a single vendor's configuration and understand why it couldn't cover the whole network
8. Wire configuration checks into a GitHub Actions workflow that runs automatically on push

# Lab Environment and Preparation

<!-- stop calling it "Lab2 ring" and call it the "network topology" or the "network" instead -->
You will need:

- Your network topology
- Your GitHub Classroom repository
- Docker and Docker Compose, already available on your VM


Addressing used in this lab, extending what previous labs already established:

| Segment | Node : Interface | Address |
|---|---|---|
| ceos1 to host1 | ceos1 : Ethernet3 | 10.0.100.1/24 |
| ceos1 to host1 | host1 : eth1 | 10.0.100.2/24 |
| ceos2 to host2 | ceos2 : Ethernet3 | 10.0.200.1/24 |
| ceos2 to host2 | host2 : eth1 | 10.0.200.2/24 |

>## If Things Go Wrong
>- Never destroy `lab-net` with `--cleanup`, it deletes the saved configuration every lab in this course, including this one, depends on.
>- The `.env` file holds your NetBox API token. Confirm it is actually excluded by `git status` before every commit in this lab, do not assume `.gitignore` is correct just because it worked in earlier labs.
>- Before running an Ansible playbook, syntax-check it first: `ansible-playbook -i <inventory> <playbook>.yml --syntax-check`.
>- Before hand-editing a saved device configuration file like `ceos1.cfg`, make a copy first (`cp ceos1.cfg ceos1.cfg.bak`). A single bad edit to a full running-config dump can break Batfish's parse for the whole snapshot, not just the line you meant to change, and the resulting error message will not point you back to your edit.
>- If a Docker container name is already in use, for example a second attempt to start Batfish or NetBox after a mistake, remove the old one before retrying: `docker rm -f batfish`.
>- If you damage the VM itself, stop and contact your instructor rather than continuing to troubleshoot.

\newpage

# Part A: NetBox as Source of Truth

## Task 0: Environment Check and NetBox Deployment

Objective: Deploy NetBox with minimal manual setup to get an API token, everything after that happens through the API.

1. NetBox Docker image is pre-installed, launch it via `docker compose`.

    ```bash
    cd ~/netbox-docker
    docker compose up -d
    ```

    Monitor the output. All volumes and containers should be created. Docker compose could timeout and report "unhealthy" for container `netbox-1`. Ignore that for now.  

2. Watch the logs for few minutes until it settles.

    ```bash
    docker compose logs -f netbox
    ```

    Press Ctrl+C once you see it serving requests.

3. You will need an API token. This token has been created for you in the `docker-compose.override.yml` file. 

    ```bash
    cat docker-compose.override.yml
    ```

4. Save the token where your scripts can find it using the format "nbt_.<SUPERUSER_API_KEY>.<SUPERUSER_API_TOKEN>".

    ```bash
    cd ~/labs
    nano .env
    ```

    ```text
    NETBOX_TOKEN=nbt_<SUPERUSER_API_KEY>.<SUPERUSER_API_TOKEN>
    NETBOX_URL=http://localhost:8000
    ```

5. Create this lab's folder structure

    ```bash
    mkdir -p lab5/scripts lab5/ansible lab5/checks
    ```
6. Activate the virtual environment install what this lab needs.

    ```bash
    source .velab/bin/activate
    pip install pynetbox python-dotenv
    pip freeze > requirements.txt
    ```

### Questions and Deliverables

1. Provide the output of docker compose logs once NetBox is up, showing it accepting connections.

## Task 1: Populating NetBox with the Existing Topology

Objective: model the network nodes in NetBox using Python's `pynetbox`.

1. Create the data file below. Two nodes are included, you need to add the third node, `srl1`, following the same pattern.

    ```bash
    cd ~/labs/lab5 && nano scripts/netbox_data.yaml
    ```

    ```yaml
    site:
      name: INWK6312 Lab
      slug: inwk6312-lab
    manufacturers:
      - name: Arista
        slug: arista
      - name: Nokia
        slug: nokia
    device_types:
      - model: cEOS
        slug: ceos
        manufacturer: arista
      - model: SR Linux
        slug: sr-linux
        manufacturer: nokia
    roles:
      - name: Router
        slug: router
        color: "2196f3"

    # IP Addresses:
    #   ceos1 Ethernet1 (10.0.12.1/30) <-> ceos2 Ethernet1 (10.0.12.2/30)
    #   ceos2 Ethernet2 (10.0.23.1/30) <-> srl1 ethernet-1/1.0 (10.0.23.2/30)
    #   srl1 ethernet-1/2.0 (10.0.13.1/30) <-> ceos1 Ethernet2 (10.0.13.2/30)
    devices:
      - name: ceos1
        device_type: ceos
        role: router
        interfaces:
          - name: Ethernet1
            address: 10.0.12.1/30
          - name: Ethernet2
            address: 10.0.13.2/30
      - name: ceos2
        device_type: ceos
        role: router
        interfaces:
          - name: Ethernet1
            address: 10.0.12.2/30
          - name: Ethernet2
            address: 10.0.23.1/30

    # TODO: add srl1, following the same pattern as ceos1 and ceos2 above.
    # device_type is sr-linux and its two interfaces are named
    # ethernet-1/1.0 and ethernet-1/2.0. Addresses are in the
    # table in the comment above.
    ```

2. Create the Python script. The script reads `netbox_data.yaml` and creates whatever it describes.

    ```bash
    nano scripts/populate_netbox.py
    ```

    ```python
    import os
    import sys
    import yaml
    import pynetbox
    from dotenv import load_dotenv

    load_dotenv()
    nb = pynetbox.api(os.environ["NETBOX_URL"], token=os.environ["NETBOX_TOKEN"])

    def get_or_create(endpoint, filters, **create_fields):
        """
        Return the existing object matching filters, or create it if it doesn't exist yet.
        Safe to run this whole script more than once.
        """

        existing = endpoint.get(**filters)
        if existing:
            return existing
        return endpoint.create(**{**filters, **create_fields})

    def main(data):

        site = get_or_create(
            nb.dcim.sites,
            {"slug": data["site"]["slug"]},
            name=data["site"]["name"],
            status="active",
        )

        manufacturers = {}
        for m in data["manufacturers"]:
            manufacturers[m["slug"]] = get_or_create(
                nb.dcim.manufacturers, {"slug": m["slug"]}, name=m["name"]
            )

        device_types = {}
        for dt in data["device_types"]:
            device_types[dt["slug"]] = get_or_create(
                nb.dcim.device_types,
                {"slug": dt["slug"]},
                model=dt["model"],
                manufacturer=manufacturers[dt["manufacturer"]].id,
            )

        device_roles = {}
        for rl in data["roles"]:
            device_roles[rl["slug"]] = get_or_create(
                nb.dcim.device_roles,
                {"slug": rl["slug"]},
                name=rl["name"],
                color=rl["color"],
            )

        for dev in data["devices"]:
            device = get_or_create(
                nb.dcim.devices,
                {"name": dev["name"], "site": site.slug},
                site=site.id,
                device_type=device_types[dev["device_type"]].id,
                role=device_roles[dev["role"]].id,
                status="active",
            )

            for iface in dev["interfaces"]:
                interface = get_or_create(
                    nb.dcim.interfaces,
                    {"device_id": device.id, "name": iface["name"]},
                    device=device.id,
                    type="other",
                )

                if "address" in iface:
                    get_or_create(
                        nb.ipam.ip_addresses,
                        {"address": iface["address"]},
                        assigned_object_type="dcim.interface",
                        assigned_object_id=interface.id,
                    )

    if __name__ == "__main__":

        if len(sys.argv) < 2:
            print("Error: Please provide a filename.")
            sys.exit(1)

        filename = sys.argv[1]

        with open(filename) as f:
            data = yaml.safe_load(f)

        main(data)

        print(
            f"NetBox populated from netbox_data.yaml: {len(data['devices'])} device(s) processed"
        )
    ```

4. Check both files before running anything. `netbox_data.yaml` is hand-edited YAML, and `populate_netbox.py` is a new script, both are worth a quick check first.

    ```bash
    python3 -c "import yaml; yaml.safe_load(open('scripts/netbox_data.yaml'))"
    python3 -m py_compile scripts/populate_netbox.py
    ```

5. Run the script.

    ```bash
    python3 scripts/populate_netbox.py scripts/netbox_data.yaml
    ```

6. Look at the result in the web UI and confirm that devices, interfaces, and addresses are there. Spend time looking around and discovering NetBox, you won't be using the UI in this lab except for checking.

### Questions and Deliverables

1. Provide your completed `netbox_data.yaml`.
2. Provide a screenshot or the text content of one device's interface list from the web UI, confirming step 6.

## Task 2: Querying NetBox over REST and GraphQL

Objective: retrieve the same data two different ways, and see why NetBox offers both.

1. Query `ceos1`'s interfaces over the REST API.

    ```bash
    curl -s -H "Authorization: Token $(grep NETBOX_TOKEN ~/labs/.env | cut -d= -f2)" \
      "http://localhost:8000/api/dcim/interfaces/?device=ceos1" | python3 -m json.tool
    ```

2. Query the same data over GraphQL, asking only for the fields you actually want, name and the addresses assigned to each interface.

    ```bash
    curl -s -H "Authorization: Token $(grep NETBOX_TOKEN ~/labs/.env | cut -d= -f2)" \
      -H "Content-Type: application/json" \
      -d '{"query": "{ interface_list(filters: {device: {name: {exact: \"ceos1\"}}}) { name ip_addresses { address } } }"}' \
      "http://localhost:8000/graphql/" | python3 -m json.tool
    ```

### Questions and Deliverables

1. Provide the output of both queries.


\newpage

# Part B: Extending the Topology from the Source of Truth

## Task 3: Adding Traffic Generating Hosts

Objective: extend the network topology file by adding two hosts that connect to the cEOS nodes.


1. Edit the network topology file.

    ```bash
    nano ~/labs/topology/lab-net.clab.yml
    ```

    Add two new nodes and two new links, alongside the three that are already there.

    ```yaml
    topology:
      nodes:
        # Add these nodes below the original nodes
        host1:
          kind: linux
          image: nicolaka/netshoot:latest
          exec:
            - ip link set dev eth1 mtu 1500
            - ip addr add 10.0.100.2/24 dev eth1
            - ip route replace 0/0 via 10.0.100.1
        host2:
          kind: linux
          image: nicolaka/netshoot:latest
          exec:
            - ip link set dev eth1 mtu 1500
            - ip addr add 10.0.200.2/24 dev eth1
            - ip route replace 0/0 via 10.0.200.1
    ```

    ```yaml
      links:
        # Add these links below the original links
        - endpoints: ["ceos1:eth3", "host1:eth1"]
        - endpoints: ["ceos2:eth3", "host2:eth1"]
    ```

    The `exec` commands in the topology file set host's default interface MTU to 1500, the IP addess of the interface and the default gateway.

2. Deploy the topology.

    ```bash
    sudo containerlab deploy -t ~/labs/topology/lab-net.clab.yml
    ```

3. The nodes should retain their past configuration, but if the configuration doesn't come back automatically, then you can apply the configuration list in the Appendix below.

4. You can quickly check if the configuration is correct and if routing works properly:

    ```bash
    docker exec ceos1 ip route
    docker exec ceos1 traceroute 10.0.23.2
    ```

    Note: you can execute the above commands directly from Docker because cEOS runs on Linux and implements the Linux IP command. 

### Questions and Deliverables

1. Provide the output of `containerlab inspect -t ~/labs/topology/lab-net.clab.yml`, showing all five nodes running.

## Task 4: Modeling the New Pieces in NetBox

Objective: extend NetBox data to cover the added nodes, keeping the source of truth in sync with the actual topology.

1. Extend `netbox_data.yaml` by adding entries for `host1` and `host2`, plus the two new router interfaces, `Ethernet3` on both `ceos1` and `ceos2`.

    ```bash
    cd ~/labs/lab5 && nano scripts/netbox_data.yaml
    ```

    Add a manufacturer, a role, and a device type for the hosts:
    
    ```yaml
    manufacturers:
      - name: Nicolaka
        slug: nicolaka
    device_types:
      - model: Generic
        slug: generic
    roles:
      - name: Host
        slug: host
        color: "ffa500"
    ```

2. Add the two host devices, `host1` and `host2`, with one interface each, and IP addresses matching the addressing table in this lab's introduction.
3. Add interface `Ethernet3` to nodes `ceos1` and `ceos2` with IP addresses matching the addressing table in this lab's introduction.
4. Save the YAML file then run `populate_netbox.py` again.

    ```bash
    python3 scripts/populate_netbox.py scripts/netbox_data.yaml
    ```

### Questions and Deliverables

1. Provide a copy of the extended `netbox_data.yaml`.
2. Query the REST API for host1's IP address, the same way you did in Task 2, and provide the output.

## Task 5: Pushing Addressing from NetBox with Ansible

Objective: use the source of truth to drive automation.

1. Create an Ansible playbook that queries NetBox for each host's Ethernet3 address rather than having that address typed into a template variable anywhere.

    ```bash
    cd ~/labs/lab5 && nano ansible/configure_hosts_interface.yml
    ```

    ```yaml
    ---
    - name: Configure host facing interface from NetBox
      hosts: ceos
      gather_facts: false
      vars:
        netbox_url: "http://localhost:8000"
        netbox_token: "{{ lookup('ansible.builtin.ini', 'NETBOX_TOKEN', type='properties', file='~/labs/.env') }}"
      tasks:
        - name: Look up this device's Ethernet 3 address in NetBox
          ansible.builtin.uri:
            url: "{{ netbox_url }}/api/ipam/ip-addresses/?device={{ inventory_hostname }}&interface=Ethernet3"
            headers:
              Authorization: "Token {{ netbox_token }}"
            return_content: true
          register: netbox_response

        - name: Extract the address from the response
          ansible.builtin.set_fact:
            host_facing_address: "{{ netbox_response.json.results[0].address }}"

        - name: Debug the extracted address
          ansible.builtin.debug:
            msg: "Extracted address: {{ host_facing_address }}"

        - name: Apply the address and join OSPF area 0.0.0.0
          arista.eos.eos_config:
            lines:
              - interface Ethernet 3
              - no switchport
              - ip address {{ host_facing_address }}
              - ip ospf area 0.0.0.0
              - no shutdown

        - name: Update OSPF configuration
          arista.eos.eos_config:
            lines:
              - no passive-interface Ethernet 3
            parents: router ospf 100
    ```

   <!-- Space is needed for "Ethernet 3", so do not remove it -->
   
2. Use the Ansible inventory from Lab4 to syntax-check, then run the playbook.

    ```bash
    ansible-playbook -i ~/labs/lab4/ansible/inventory.yml ansible/configure_hosts_interface.yml --syntax-check
    ansible-playbook -i ~/labs/lab4/ansible/inventory.yml ansible/configure_hosts_interface.yml
    ```

3. Verify on the network node.

    ```bash
    ansible -i ~/labs/lab4/ansible/inventory.yml ceos -m arista.eos.eos_command -a "commands='show ip interface brief'"
    ansible -i ~/labs/lab4/ansible/inventory.yml ceos -m arista.eos.eos_command -a "commands='show ip route ospf'"
    ```

4. Verify from both hosts, using their Ethernet1 interfaces addresses instead of their hostnames. `host1` and `host2` resolve through /etc/hosts to their management addresses, not their Ethernet1 ones, so pinging by hostname here would test the wrong path entirely.

    ```bash
    docker exec host1 traceroute 10.0.200.2
    docker exec host2 ping -c 5 10.0.100.2
    ```

### Questions and Deliverables

1. Provide the output of step 3, and the ping output from step 4.
2. If you changed host1's address in NetBox and reran this playbook, with nothing else touched, what would you expect Ansible to report, ok or changed? What does that tell you about where this playbook's actual source of truth lives?

\newpage

# Part C: Traffic and Telemetry

## Task 6: Generating Traffic with iperf3

Objective: create sustained traffic between the two hosts.

1. Start an iperf3 server on host2.

    ```bash
    docker exec host2 iperf3 -s -D
    ```

2. Run a client test from `host1` for 30 seconds at 1Mbps. You must use the IP address of the destination rather than its name. Why?

    ```bash
    docker exec host1 iperf3 -c 10.0.200.2 -t 30 -b 1M
    ```

### Questions and Deliverables

1. Provide the summary line from the end of the `iperf3` output, showing the achieved throughput.

## Task 7: Watching Real Telemetry

Objective: reuse gNMI subscribe script from Lab 4 to report telemetry from `ceos2`.

1. Copy `subscribe_sample.py` from Lab 4 and change the node to `ceos1` and the path.

    ```bash
    cd ~/labs/lab5/scripts && cp ~/labs/lab4/scripts/subscribe_sample.py subscribe_ceos_traffic.py
    nano subscribe_ceos_traffic.py
    ```

    ```python
    import json
    from pygnmi.client import gNMIclient, telemetryParser
    from devicelib import load_devices

    devices = load_devices("gnmi")
    ceos1 = devices["ceos1"]

    subscribe_request = {
        "subscription": [
            {
                "path": "interfaces/interface[name=Ethernet3]/state/counters/in-octets",
                "mode": "sample",
                "sample_interval": 10000000000,
            }
        ],
        "mode": "stream",
        "encoding": "json",
    }

    with gNMIclient(**ceos1) as gc:
        telemetry_stream = gc.subscribe(subscribe=subscribe_request)
        for response in telemetry_stream:
            print(json.dumps(telemetryParser(response), indent=2))
    ```

    This watches Ethernet3, `ceos1`'s link to `host1` which is generating the traffic towards `host2`.

2. Check it compiles, then start the script, and in a second terminal, run another iperf3 test while it's running.

    ```bash
    python3 -m py_compile subscribe_ceos_traffic.py
    python3 subscribe_ceos_traffic.py
    ```

    In a second terminal:

    ```bash
    docker exec host2 iperf3 -s -D
    docker exec host1 iperf3 -c 10.0.200.2 -t 30 -b 1M
    ```

3. Watch the counter values between updates, the difference between consecutive samples should track roughly with the throughput iperf3 reported.

4. Stop the script with Ctrl+C once the test finishes.

### Questions and Deliverables

1. Provide about a minute of output from step 2, spanning before, during, and after the iperf3 run.
2. Pick two consecutive samples taken during the iperf3 run. The difference in out-octets between them, divided by the 10 second sample interval, gives you an average byte rate. How does that compare to the throughput iperf3 itself reported in Task 6?



\newpage

# Part D: A CI/CD Pipeline with Ansible and Batfish

## Task 8: Ansible Based Verification

Objective: write verification tasks that check live state against what you expect, extending the register and assert pattern from Lab 4's compliance check.

1. Create the playbook.

    ```bash
    cd ~/labs/lab5 && nano ansible/verify_network.yml
    ```

    ```yaml
    ---
    - name: Verify OSPF and reachability
      hosts: ceos
      gather_facts: false
      tasks:
        - name: Check OSPF neighbor state
          arista.eos.eos_command:
            commands:
              - show ip ospf neighbor
          register: ospf_output

        - name: Assert both expected neighbors are FULL
          ansible.builtin.assert:
            that:
              - "'FULL' in ospf_output.stdout[0]"
            fail_msg: "No FULL OSPF neighbors found"
            success_msg: "OSPF adjacency confirmed"
    ```

2. Syntax-check it, then run it.

    ```bash
    ansible-playbook -i ~/labs/lab4/ansible/inventory.yml ansible/verify_network.yml --syntax-check
    ansible-playbook -i ~/labs/lab4/ansible/inventory.yml ansible/verify_network.yml
    ```

### Questions and Deliverables

1. Provide the output of step 2.
2. This check only confirms the word FULL appears somewhere in the output, it doesn't count how many neighbors, or check which specific ones. Extend the assert condition to also fail if fewer than 2 neighbors show FULL, and provide your modified task.

## Task 9: Configuring and Verifying NTP with Batfish Checks for cEOS

Objective: add NTP configuration to cEOS nodes. Before touching the production network, use Ansible to back up the config, add NTP configuration to the configuration files, then use Batfish to test the correctness of the NTP configuration and reachability to the NTP server.

Note: Batfish has no support for Nokia SR Linux at the moment, so this Task only covers `ceos1` and `ceos2`.

1. Start Batfish, its Docker image has already been pulled into your machine. If a container named `batfish` already exists from an earlier attempt, remove it first: `docker rm -f batfish`.

    ```bash
    cd ~/labs
    docker run -d --name batfish -p 9997:9997 -p 9996:9996 batfish/allinone
    pip install pybatfish
    pip freeze > requirements.txt
    ```

2. Pull `ceos1` and `ceos2`'s running configs into a snapshot folder.

    ```bash
    mkdir -p ~/labs/lab5/checks/ceos/configs
    ```

    ```bash
    nano ~/labs/lab5/ansible/backup_configs.yml
    ```

    ```yaml
    ---
    - name: Back up running configuration
      hosts: ceos
      gather_facts: false
      tasks:
        - name: Retrieve running config
          arista.eos.eos_command:
            commands:
              - show running-config
          register: running_config

        - name: Save to snapshot folder
          ansible.builtin.copy:
            content: "{{ running_config.stdout[0] }}"
            dest: "/home/student/labs/lab5/checks/ceos/configs/{{ inventory_hostname }}.cfg"
    ```

    Syntax-check it, then run it.

    ```bash
    ansible-playbook -i ~/labs/lab4/ansible/inventory.yml ~/labs/lab5/ansible/backup_configs.yml --syntax-check
    ansible-playbook -i ~/labs/lab4/ansible/inventory.yml ~/labs/lab5/ansible/backup_configs.yml
    ```

3. Before editing, make a backup copy of each config file, a bad edit here can break Batfish's parse for the whole snapshot, and having the original to diff against or fall back to is worth the ten seconds.

    ```bash
    cp ~/labs/lab5/checks/ceos/configs/ceos1.cfg ~/labs/lab5/checks/ceos/configs/ceos1.cfg.bak
    cp ~/labs/lab5/checks/ceos/configs/ceos2.cfg ~/labs/lab5/checks/ceos/configs/ceos2.cfg.bak
    ```

4. Edit `ceos1`'s configuration file to add NTP near the end of the file, then save.

    ```bash
    nano ~/labs/lab5/checks/ceos/configs/ceos1.cfg
    ```

    ```text
    !
    ntp server 172.20.20.1
    end
    ```

5. Repeat for `ceos2`, but use a different (incorrect) server.

    ```text
    !
    ntp server 1.1.1.1
    end
    ```


6. Write the check. This confirms NTP is configured, the server IP address is among an approved list of servers, and the server is reachable.

    ```bash
    nano ~/labs/lab5/checks/batfish_ntp_check.py
    ```

    ```python
    from pybatfish.client.session import Session
    from pybatfish.datamodel.flow import HeaderConstraints, PathConstraints

    bf = Session(host="localhost")
    bf.set_network("lab5")
    bf.init_snapshot(
        "ceos",
        name="snapshot",
        extra_args={"ignoremanagementinterfaces": False},
        overwrite=True,
    )

    COL_NAME = "NTP_Servers"

    # 1. Fetch configured NTP servers using nodeProperties
    node_props = bf.q.nodeProperties(properties=COL_NAME).answer().frame()

    # Define the reference set of allowed/expected NTP servers
    ref_ntp_servers = set(["172.20.20.1"])

    # 2. Find nodes that have no NTP server in common with the reference set
    ns_violators = node_props[
        node_props[COL_NAME].apply(lambda x: len(ref_ntp_servers.intersection(set(x))) == 0)
    ]

    print("--- NTP Policy Violations ---")
    if not ns_violators.empty:
        print("FAIL: Nodes with no overlapping reference NTP servers found:")
        print(ns_violators[["Node", COL_NAME]])
        raise SystemExit(1)
    else:
        print("PASS: All nodes have at least one valid NTP server from the reference set.")

    # 3. Verify network reachability to the validated NTP server(s)
    print("\n--- NTP Server Reachability Check ---")
    all_reachable = True

    # Retrieve all node names dynamically
    nodes_df = bf.q.nodeProperties().answer().frame()

    for node in node_props["Node"]:
        for ip in ref_ntp_servers:
            headers = HeaderConstraints(dstIps=ip, ipProtocols=["UDP"], dstPorts=["123"])

            r_df = (
                bf.q.reachability(
                    pathConstraints=PathConstraints(startLocation=f"{node}[Management0]"),
                    headers=headers,
                    actions="Delivered_to_subnet",
                )
                .answer()
                .frame()
            )

            # Check if any trace reached an ACCEPTED status
            reachable = False
            if not r_df.empty and "Traces" in r_df.columns:
                reachable = any(
                    trace.disposition == "DELIVERED_TO_SUBNET"  # "ACCEPTED"
                    for traces in r_df["Traces"]
                    for trace in traces
                )

            if reachable:
                print(f"PASS: Node '{node}' can reach NTP server {ip} on UDP 123.")
            else:
                print(f"FAIL: Node '{node}' cannot reach NTP server {ip}.")
                all_reachable = False

    if not all_reachable:
        raise SystemExit(1)
    ```

7. Run it. The check should fail because server `1.1.1.1` is not among the approved servers.

    ```bash
    cd ~/labs/lab5/checks && python3 batfish_ntp_check.py
    ```

### Questions and Deliverables

1. Provide the output of step 7, showing a check failure due to ceos2's unapproved NTP server.
2. The reachability check confirms Batfish's model routes NTP traffic toward 172.20.20.1's subnet. What could this check miss that only testing against the live network could catch?

## Task 10: Wrapping It in GitHub Actions

Objective: run the checks from Task 9 automatically whenever configuration work gets pushed to GitHub.

1. Create the workflow file in your repository.

    ```bash
    cd ~/labs && mkdir -p ~/labs/.github/workflows
    nano ~/labs/.github/workflows/config-check.yml
    ```

    ```yaml
    name: Config Checks

    on:
      push:
        paths:
          - "lab5/checks/**"

    jobs:
      batfish-check:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4.2.2

          - name: Set up Python
            uses: actions/setup-python@v5
            with:
              python-version: "3.11"

          - name: Start Batfish
            run: docker run -d --name batfish -p 9997:9997 -p 9996:9996 batfish/allinone

          - name: Install pybatfish
            run: pip install pybatfish

          - name: Wait for Batfish service
            run: |
              echo "Waiting for Batfish container to accept connections..."
              for i in {1..30}; do
                if curl -s http://localhost:9997/ > /dev/null 2>&1 || nc -z localhost 9997; then
                  echo "Batfish is ready after ${i} seconds!"
                  exit 0
                fi
                sleep 1
              done
              echo "Timed out waiting for Batfish."
              exit 1

          - name: Run configuration check
            run: python3 batfish_ntp_check.py
            working-directory: lab5/checks
    ```

2. Check this file's YAML is well formed before committing it, a bad indent here fails silently until GitHub tries to run it.

    ```bash
    python3 -c "import yaml; yaml.safe_load(open('.github/workflows/config-check.yml'))"
    ```

3. Commit and push just this file, then confirm it actually caught nothing to run yet, this workflow only triggers on changes under lab5/checks.

    GitHub won't accept a push that adds or modifies a file under .github/workflows/ using a token that only has repo scope, the scope Lab 1 had you create. It requires a token with the workflow scope specifically. Check your token's scopes on GitHub under Settings, Developer settings, Personal access tokens, and add workflow if it isn't already there, or generate a new token with both scopes and use that instead.

    ```bash
    cd ~/labs
    git add .github/workflows/config-check.yml
    git commit -m "Add config check workflow"
    git push
    ```

4. Add the checks folder, then commit and push. `ceos2.cfg` is still carrying the deliberate error from Task 9, so this push should trigger a failing run.

    ```bash
    git add lab5/checks/
    git commit -m "Add checks folder"
    git push
    ```

5. Confirm the Actions tab shows a failed run this time, and that the log names the actual reason, no overlapping reference NTP servers found.
6. Change the server IP to "172.20.20.1" in `ceos2`, then repeat step 4 and confirm that the check passes.

### Questions and Deliverables

1. Provide a link to your GitHub Actions run history, or paste the relevant log excerpt, showing one failing run and one passing run.
2. The workflow only triggers on changes under lab5/checks, not on every push to the repository. Why does that scoping matter, given this repository also contains other files?

## Task 11: Committing Your Work

Objective: bring the rest of this lab's files into your repository.

1. Move to the root of your repository.

    ```bash
    cd ~/labs && git status
    ```

2. Stage and confirm what is about to be committed.

    ```bash
    git add topology/lab-net.clab.yml lab5 requirements.txt
    git status
    ```

3. Commit and push.

    ```bash
    git commit -m "Add Lab 5, NetBox source of truth, real traffic telemetry, and CI/CD pipeline"
    git push
    ```

4. Tag this checkpoint, the last one for the course.

    ```bash
    git tag lab5-complete
    ```

### Questions and Deliverables

1. Provide the output of `git log --oneline -5` after your commit.

# Clean Up

Save the network's configuration, then destroy it.

```bash
sudo containerlab save -t ~/labs/topology/lab-net.clab.yml
sudo containerlab destroy -t ~/labs/topology/lab-net.clab.yml
```

NetBox and Batfish are not part of the saved topology state, stop them separately if you want to reclaim the resources.

```bash
cd ~/netbox-docker && docker compose down
docker stop batfish && docker rm batfish
```

<!-- or 
cd ~/netbox-docker && docker compose down -v 
to remove all databases
-->


Deactivate your virtual environment.

```bash
deactivate
```

# Submission

Confirm your repository includes, at minimum, the following, then submit as instructed by your course delivery platform:

- The modified labs/topology/lab-net.clab.yml, with host1 and host2 added
- lab5/scripts/populate_netbox.py and subscribe_ceos_traffic.py
- lab5/ansible/configure_hosts_interface.yml, verify_network.yml, and backup_configs.yml
- lab5/checks/batfish_ntp_check.py
- .github/workflows/config-check.yml
- Your answers to the Questions and Deliverables sections, submitted as your lab report per your instructor's separate instructions

\newpage

# Appendix: Command Summary

## NetBox

| Command | Usage |
|---|---|
| docker compose up -d | Start the NetBox stack in the background |
| docker compose logs -f netbox | Follow NetBox's startup logs |
| pynetbox.api(url, token=token) | Open an API session from Python |
| nb.dcim.devices.create(...) | Create a device |
| nb.ipam.ip_addresses.create(...) | Create and optionally assign an IP address |

## Ansible

| Call | Usage |
|---|---|
| ansible.builtin.uri | Make an HTTP request, used here to query NetBox's REST API |
| ansible.builtin.set_fact | Store a value extracted from a previous task's result |
| until / retries / delay | Retry a task until a condition in its result is met |

## Batfish

| Call | Usage |
|---|---|
| Session(host="localhost") | Connect to a running Batfish instance |
| bf.init_snapshot(folder, name=, overwrite=) | Load a folder of device configs as a snapshot |
| bf.q.interfaceProperties().answer().frame() | Query interface state as a table |
| bf.q.ospfInterfaceConfiguration().answer().frame() | Query per-interface OSPF configuration as a table |

## iperf3

| Command | Usage |
|---|---|
| iperf3 -s | Run as a server, listening for a client |
| iperf3 -c \<address\> -t \<seconds\> | Run as a client against a server for a fixed duration |

## Default Credentials

| Kind | Username | Password |
|---|---|---|
| Arista cEOS | admin | admin |
| Nokia SR Linux | admin | NokiaSrl1! |
| NetBox | admin | admin |

# Appendix: Node Configuration

Copy and paste the configuration below into each network node.

## ceos1

```text
interface Ethernet1
   no switchport
   ip address 10.0.12.1/30
   ip ospf area 0.0.0.0
!
interface Ethernet2
   no switchport
   ip address 10.0.13.2/30
   ip ospf area 0.0.0.0
!
interface Loopback0
   ip address 10.255.0.1/32
   ip ospf area 0.0.0.0
!
interface Management0
   ip address 172.20.20.2/24
   ipv6 address 3fff:172:20:20::2/64
!
ip routing
!
router ospf 100
   router-id 10.255.0.1
   passive-interface default
   no passive-interface Ethernet1
   no passive-interface Ethernet2
   no passive-interface Loopback0
   max-lsa 12000
!
end
```

## ceos2

```text
interface Ethernet1
   no switchport
   ip address 10.0.12.2/30
   ip ospf area 0.0.0.0
!
interface Ethernet2
   description Link to srl1
   no switchport
   ip address 10.0.23.1/30
   ip ospf area 0.0.0.0
!
interface Loopback0
   ip address 10.255.0.2/32
   ip ospf area 0.0.0.0
!
interface Management0
   ip address 172.20.20.4/24
   ipv6 address 3fff:172:20:20::4/64
!
ip routing
!
router ospf 100
   router-id 10.255.0.2
   passive-interface default
   no passive-interface Ethernet1
   no passive-interface Ethernet2
   no passive-interface Loopback0
   max-lsa 12000
!
end
```

## srl1

<!--
info flat | filter interface
info flat | filter network-instance
-->

```text
set / interface ethernet-1/1 admin-state enable
set / interface ethernet-1/1 subinterface 0 ipv4 admin-state enable
set / interface ethernet-1/1 subinterface 0 ipv4 address 10.0.23.2/30
set / interface ethernet-1/2 admin-state enable
set / interface ethernet-1/2 subinterface 0 ipv4 admin-state enable
set / interface ethernet-1/2 subinterface 0 ipv4 address 10.0.13.1/30

set / interface system0 admin-state enable
set / interface system0 subinterface 0 ipv4 admin-state enable
set / interface system0 subinterface 0 ipv4 address 10.255.0.3/32

set / network-instance default interface ethernet-1/1.0
set / network-instance default interface ethernet-1/2.0
set / network-instance default interface system0.0
set / network-instance default protocols ospf instance 100 admin-state enable
set / network-instance default protocols ospf instance 100 version ospf-v2
set / network-instance default protocols ospf instance 100 router-id 10.255.0.3
set / network-instance default protocols ospf instance 100 area 0.0.0.0 interface ethernet-1/1.0 admin-state enable
set / network-instance default protocols ospf instance 100 area 0.0.0.0 interface ethernet-1/2.0 admin-state enable
set / network-instance default protocols ospf instance 100 area 0.0.0.0 interface system0.0 admin-state enable
```