---
title: INWK6312 - Lab 4
subtitle: Streaming Telemetry with gNMI and Configuration Management with Ansible
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
---

\newpage

# Introduction

This configures OSPF routing across the whole network using gNMI for Nokia SR Linux node and Ansible for Arista cEOS nodes. In the first part of the lab, you will use gNMI to discover what SR Linux supports, pulling a plain snapshot with Get, writing your own script to receive a live Subscribe stream, then configuring OSPF through the CLI to add a loopback interface with a script of your own using gNMI Set. In the second part, you will install Ansible and use it to push configuration to the cEOS nodes, an interface description first, then OSPF.

This lab starts by redeploying the network topology from previous labs. If the nodes' configuration doesn't come back with it, redeploy and reconfigure using Lab 2 Tasks 3 and 4 before continuing.

# Lab Objectives

By the end of this lab, you will be able to:

1. Discover a device's gNMI capabilities and supported models, and retrieve a configuration snapshot with a plain Get
2. Write a Python script using `pygnmi` to receive a live gNMI Subscribe stream
3. Compare SAMPLE and ON_CHANGE telemetry modes by observing their actual behavior against a live device
4. Read back a live device's configuration over gNMI and identify which YANG module actually owns it
5. Use gNMI Set to add a single new piece to an already running configuration without disturbing what's already there
6. Build an Ansible inventory with the connection variables a real network device needs
7. Use Ansible to gather facts, register output, and display it with debug
8. Render a Jinja2 template and push it to a device with a config module
9. Demonstrate idempotency and check mode, and explain what each one actually proves
10. Write and deliberately break an Ansible compliance check using assert
11. Push a multi-line routing protocol configuration with Ansible across two devices and confirm, with a ping, that it changed what the network can actually reach

# Lab Environment and Preparation

You will need:

- Your assigned Ubuntu VM IP address provided in Brightspace: ________________.
- Your containerlab topology, redeployed from its saved state.
- Your GitHub Classroom repository.

gNMI runs on TCP port 57400 on `srl1` and 6030 on `ceos1` and `ceos2`, both enabled by default. Ansible is not installed on your VM yet.

OSPF addressing used throughout this lab:

| Node | Router ID |
|---|---|
| ceos1 | 10.255.0.1 |
| ceos2 | 10.255.0.2 |
| srl1 | 10.255.0.3 |

\newpage

# Part A: gNMI and Streaming Telemetry

## Task 0: Environment Check and Tooling Setup

Objective: bring the network topology back up, create the lab folder structure, and install required tools.

1. Check if the network topology is still active (it shouldn't be).

    ```bash
    sudo containerlab inspect -t ~/labs/topology/lab-net.clab.yml
    ```

2. Redeploy the network topology from its saved state.

    ```bash
    sudo containerlab deploy -t ~/labs/topology/lab-net.clab.yml
    ```

3. Check if interface addressing is present. If not, reconfigure the devices using the Appendix below. A faster way to check is to ping.

    ```bash
    docker exec -it ceos1 Cli -c "ping 10.0.12.2"
    docker exec -it ceos1 Cli -c "ping 10.0.13.1"
    docker exec -it ceos2 Cli -c "ping 10.0.23.2"
    ```

4. Create this lab's folder structure.

    ```bash
    mkdir -p ~/labs/lab4/scripts ~/labs/lab4/ansible/templates
    ```

5. Activate Python's virtual environment.

    ```bash
    cd ~/labs
    source .velab/bin/activate
    ```

6. Install this lab's Python packages.

    ```bash
    pip install ansible-core
    pip freeze > requirements.txt
    ```

7. Confirm that everything needed is in place.

    ```bash
    python3 -c "import pygnmi; print('pygnmi ok')"
    ansible --version
    ansible-galaxy collection list | grep eos
    ```

8. If the EOS collection from step 6 is not bundled with ansible-core, install it separately.

    ```bash
    ansible-galaxy collection install arista.eos
    ```

### Questions and Deliverables

1. Provide the output of Step 7 above.


## Task 1: Discovering Supported Modules with gNMI

Objective: discover what OSPF modules each device supports over gNMI.

1. List `srl1`'s supported models.

    ```bash
    cd ~/labs/tools
    ./gnmi_tool.py srl1 modules | grep -i ospf
    ```

2. Do the same for `ceos1`.

    ```bash
    ./gnmi_tool.py ceos1 modules | grep -i ospf
    ```

3. Compare the organization field between the two outputs.

### Questions and Deliverables

1. Provide both outputs from steps 1 and 2.
2. Both devices advertise OSPF modules, but are the two devices reporting the exact same set of modules? Support your answer.

## Task 2: A Plain gNMI Get

Objective: retrieve a configuration snapshot with a single Get, the gNMI equivalent of NETCONF's `get-config`, and compare the shape of the response.

1. Retrieve the interfaces tree from `srl1`.

    ```bash
    ./gnmi_tool.py srl1 config /interface
    ```

### Questions and Deliverables

1. Provide the output.
2. This came back as JSON, Lab 3's NETCONF `get-config` came back as XML, from the same underlying module. What does that tell you about the relationship between a YANG module and the encoding used to carry it on the wire?

## Task 3: Streaming Telemetry in SAMPLE Mode

Objective: write your own script to receive a live stream of telemetry data from `srl1`.

1. Create the script.

    ```bash
    cd ~/labs/lab4/scripts
    nano subscribe_sample.py
    ```

    <!-- Nokia uses Nokia Native model in this case -->

    <!-- the path works without the subinterface but I wanted to be consistent with
    the configuration  -->

    ```python
    import sys
    import os
    # Needed to import devicelib    
    sys.path.append(os.path.expanduser("~/labs/tools"))

    import json
    from pygnmi.client import gNMIclient, telemetryParser
    from devicelib import load_devices

    devices = load_devices("gnmi")
    srl1 = devices["srl1"]

    subscribe_request = {
        "subscription": [
            {
                "path": "/interface[name=ethernet-1/1]/subinterface[index=0]/statistics/in-octets",
                "mode": "sample",
                "sample_interval": 10000000000,
            }
        ],
        "mode": "stream",
        "encoding": "json",
    }

    with gNMIclient(**srl1) as gc:
        telemetry_stream = gc.subscribe(subscribe=subscribe_request)
        for response in telemetry_stream:
            print(json.dumps(telemetryParser(response), indent=2))
    ```

    sample_interval is in nanoseconds, 10000000000 is 10 seconds.

2. Run it, and let it collect for at least 30 seconds before stopping it with Ctrl+C.

    ```bash
    python3 subscribe_sample.py
    ```

3. Watch what arrives. You should see an update roughly every 10 seconds, whether or not traffic actually changed the counter in that window.

### Questions and Deliverables

1. Provide about 30 seconds of output from step 2.
2. SAMPLE mode sent you an update every 10 seconds regardless of whether `in-octets` actually changed. What would be wasteful about using SAMPLE mode for something that changes rarely, like whether a link is up or down?

## Task 4: Streaming Telemetry in ON_CHANGE Mode

Objective: subscribe to the same counter from Task 3, but in `ON_CHANGE` mode, in a topology quiet enough that it stays silent until you generate traffic yourself.

1. Copy your script and switch it to on_change mode instead of sample.

    ```bash
    cp subscribe_sample.py subscribe_onchange.py
    nano subscribe_onchange.py
    ```

    Change the subscription to:

    ```python
    subscribe_request = {
        "subscription": [
            {
                "path": "/interface[name=ethernet-1/1]/subinterface[index=0]/statistics/in-octets",
                "mode": "on_change",
            }
        ],
        "mode": "stream",
        "encoding": "json",
    }
    ```

    Note there is no `sample_interval`, `ON_CHANGE` doesn't sample on a timer.

    Note: A link flap is another way to trigger a change, but Containerlab builds network links as virtual Ethernet pairs. Shutting down an interface inside one container doesn't bring down the peer container's interface.

2. Run it.

    ```bash
    python3 subscribe_onchange.py
    ```

    You should see one initial update, then nothing. That initial update is `srl1` telling you the current state before settling into pure event driven mode.

3. Without stopping the script, open a second terminal and ping the node  from `ceos2`'s `Ethernet2`.

    ```bash
    ssh admin@ceos2
    ```

    ```text
    ping 10.0.23.2
    ```

    or via Docker.

    ```bash
    docker exec -it ceos2 Cli -c "ping 10.0.23.2"
    ```

4. Watch your `subscribe_onchange.py` terminal, an update should arrive while the ping is running.

5. Ping again and watch for a second update.

6. Stop the script with Ctrl+C once you've seen both updates.

Note: in this network, there is virtually no traffic across the link except for the ICMP packets generated by ping. In production networks, there is likely traffic generated by many sources. In that case, sampling is a better strategy.

### Questions and Deliverables

1. Provide the output of `subscribe_onchange.py` from step 2 through step 6, showing the initial update and both ping-triggered updates.
2. Contrast this with Task 3. How many messages did ON_CHANGE send you over the same few minutes, compared to how many SAMPLE would have sent over that same window?
3. gNMI also defines a TARGET_DEFINED mode, where the device itself picks the most appropriate mode for a given path instead of you specifying SAMPLE or ON_CHANGE yourself. Based on what you just observed, what tradeoff is the device making on your behalf when you choose TARGET_DEFINED?

## Task 5: Bringing Up OSPF on srl1

Objective: configure OSPF on `srl1` through the CLI.

1. Connect and apply the configuration. This does two things, addresses `srl1`'s loopback, `system0`, and brings up an OSPF process on the two data links.

    ```bash
    ssh admin@srl1
    ```

    ```text
    enter candidate
    set / interface system0 admin-state enable
    set / interface system0 subinterface 0 ipv4 admin-state enable
    set / interface system0 subinterface 0 ipv4 address 10.255.0.3/32
    set / network-instance default interface system0.0
    set / network-instance default protocols ospf instance 100 admin-state enable
    set / network-instance default protocols ospf instance 100 version ospf-v2
    set / network-instance default protocols ospf instance 100 router-id 10.255.0.3
    set / network-instance default protocols ospf instance 100 area 0.0.0.0 interface ethernet-1/1.0 admin-state enable
    set / network-instance default protocols ospf instance 100 area 0.0.0.0 interface ethernet-1/2.0 admin-state enable
    ```

    Check the confiuration then commit.

    ```bash
    diff
    commit now
    quit
    ```

2. Notice what this did and didn't do. `system0` now has an address and belongs to the default network-instance, but it isn't part of the OSPF area yet, only `ethernet-1/1.0` and `ethernet-1/2.0` are. Adding `system0` to the area is Task 7's.

3. You won't see a full adjacency yet, `ceos1` and `ceos2` don't have OSPF configured until Task 13, in Part B. This task's own verification happens over gNMI, next.

### Questions and Deliverables

1. Provide the output of the diff command from step 1, before you committed.
2. Why does instance 100 need a router-id set explicitly, rather than srl1 picking one on its own the way it might for other identifiers?

## Task 6: Reading Back OSPF Configuration with gNMI

Objective: confirm the CLI change and see which YANG module actually owns OSPF configuration on `srl1`.

1. Query srl1's OSPF configuration.

    ```bash
    cd ~/labs/tools
    ./gnmi_tool.py srl1 config /network-instance[name=default]/protocols/ospf
    ```

2. Look at the module name in the returned path and the values underneath it.

### Questions and Deliverables

1. Provide the output of step 1.
2. What YANG model is used for OSPF configuration?

## Task 7: Adding the Loopback to OSPF with gNMI Set

Objective: write your own script that adds one specific piece to an already running configuration.

1. Using the path structure you just read in Task 6, write a script that adds `system0.0` as a new interface entry under the existing area.

    ```bash
    cd ~/labs/lab4/scripts
    nano set_ospf_loopback.py
    ```

    ```python
    import sys
    import os
    sys.path.append(os.path.expanduser("~/labs/tools"))
    from pygnmi.client import gNMIclient
    from devicelib import load_devices

    devices = load_devices("gnmi")
    srl1 = devices["srl1"]

    path = "network-instance[name=default]/protocols/ospf/instance[name=100]/area[area-id=0.0.0.0]/interface[interface-name=system0.0]"
    value = {"admin-state": "enable"}

    with gNMIclient(**srl1) as gc:
        result = gc.set(update=[(path, value)])
        print(result)
    ```

2. Run it.

    ```bash
    python3 set_ospf_loopback.py
    ```

3. Confirm the change is successfull using the same Get from Task 6.

    ```bash
    ~/labs/tools/gnmi_tool.py srl1 config /network-instance[name=default]/protocols/ospf
    ```

    The area 0.0.0.0's interface list should now show three entries instead of two.

### Questions and Deliverables

1. Provide the output of step 2 and step 3.
2. This script called gc.set(update=[...]), not gc.set(replace=[...]). Based on what *update* and *replace* mean differently in gNMI, what would you expect to happen to `ethernet-1/1.0` and `ethernet-1/2.0`'s area membership if you had used *replace* instead, targeting just this one new interface path?


\newpage

# Part B: Configuration Management with Ansible

## Task 8: Building the Inventory

Objective: describe `ceos1` and `ceos2` to Ansible, including the connection details a real network device needs that a Linux server wouldn't.

1. Create the inventory file (pay attention to the indentation).

    ```bash
    cd  ~/labs/lab4/ansible
    nano inventory.yml
    ```

    ```yaml
    all:
      children:
        ceos:
          hosts:
            ceos1:
              ansible_host: ceos1
            ceos2:
              ansible_host: ceos2
          vars:
            ansible_connection: ansible.netcommon.network_cli
            ansible_network_os: arista.eos.eos
            ansible_user: admin
            ansible_password: admin
            ansible_become: true
            ansible_become_method: enable
            ansible_ssh_extra_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
    ```

    The variables `ansible_become` and `ansible_become_method` tell Ansible to escalate privileges on a network device after establishing the SSH connection. Specifically, `ansible_become: true` turns on privilege escalation, while `ansible_become_method: enable` instructs Ansible to use the network-standard `enable` command rather than Linux's default `sudo`.

2. Verify connectivity with an ad hoc command, before writing any playbook.

    ```bash
    ansible -i inventory.yml ceos -m arista.eos.eos_command -a "commands='show version'"
    ```

### Questions and Deliverables

1. Provide the output of step 2 for both hosts.
2. If `ansible_become` had been left out of the inventory, what specific kind of task would you expect to fail, one that only reads state, or one that changes configuration? Why?
3. Modify the command in Task 8 Step 2 above to retrieve the routing table from devices. Provide the output. 

## Task 9: Gathering Facts

Objective: use a facts module to pull structured information off both devices, and see it stored as variables you can act on later in the same play.

1. Create the playbook.

    ```bash
    nano facts.yml
    ```

    ```yaml
    ---
    - name: Gather EOS Facts
      hosts: ceos
      gather_facts: false
      tasks:
        - name: Collect EOS facts
          arista.eos.eos_facts:

        - name: Display EOS version
          ansible.builtin.debug:
            var: ansible_facts.net_version
    ```

2. Run it.

    ```bash
    ansible-playbook -i inventory.yml facts.yml
    ```

### Questions and Deliverables

1. Provide the output of step 2.
2. Module `eos_facts` collects far more than just the version, serial number, interface list, neighbor information. If a Source of Truth system were populated automatically instead of by hand, which one or two of these fields would be most useful to feed into it, and why?

## Task 10: Templating and Pushing Configuration

Objective: render a Jinja2 template and push it to both devices with a config module, rather than hardcoding the same lines twice.

1. Create the template. Both ceos1 and ceos2 reach srl1 over their own Ethernet2, so the same template applies to both hosts unchanged.

    ```bash
    nano templates/description.j2
    ```

    ```jinja
    interface Ethernet2
       description Link to srl1
    ```

2. Create the playbook to push a rendered template.

    ```bash
    nano configure_description.yml
    ```

    ```yaml
    ---
    - name: Configure Interface Description
      hosts: ceos
      gather_facts: false
      tasks:
        - name: Apply templated interface description
          arista.eos.eos_config:
            content: "{{ lookup('ansible.builtin.template', 'templates/description.j2') }}"
    ```

3. Run it.

    ```bash
    ansible-playbook -i inventory.yml configure_description.yml
    ```

    Both hosts should report changed.

4. Verify the change using an ad hoc command.

    ```bash
    ansible -i inventory.yml ceos -m arista.eos.eos_command -a "commands='show interface description'"
    ```

    Repeat for ceos2.

### Questions and Deliverables

1. Provide the playbook run output from step 3, showing changed for both hosts.
2. Provide the show interfaces description output from both hosts in step 4, confirming the configuration change.

## Task 11: Idempotency and Check Mode

Objective: confirm that a second identical run does nothing, and that check mode shows you a change before it happens.

1. Run the exact same playbook from Task 10 again, with no changes to the template.

    ```bash
    ansible-playbook -i inventory.yml configure_description.yml
    ```

    This time both hosts should report ok, not changed. Nothing was different on the device, so Ansible had nothing to do.

2. Now change the template's description text.

    ```bash
    nano templates/description.j2
    ```

    ```jinja
    interface Ethernet2
       description Link to Another Node
    ```

3. Preview the change without applying it.

    ```bash
    ansible-playbook -i inventory.yml configure_description.yml --check --diff
    ```

4. Confirm on the device that nothing actually changed yet.

    ```bash
    ansible -i inventory.yml ceos -m arista.eos.eos_command -a "commands='show interface description'"
    ```

5. Apply the change.

    ```bash
    ansible-playbook -i inventory.yml configure_description.yml
    ```

### Questions and Deliverables

1. Provide the output of step 1, showing ok instead of changed.
2. Provide the output of step 3, the `--check --diff` preview.
3. `--check` alone tells you whether something would change. Based on what you saw in step 3, what did adding `--diff` show you on top of that?

## Task 12: A Compliance Check with Assert

Objective: write an automated check that a specific piece of configuration matches what it should, then watch it correctly fail when that's no longer true.

1. Create the playbook.

    ```bash
    nano compliance_check.yml
    ```

    ```yaml
    ---
    - name: Verify Interface Description Compliance
      hosts: ceos
      gather_facts: false
      vars:
        expected_description: "Link to srl1"
      tasks:
        - name: Retrieve current interface description
          arista.eos.eos_command:
            commands:
              - show interfaces description
          register: desc_output

        - name: Assert Ethernet2 matches the expected description
          ansible.builtin.assert:
            that:
              - expected_description in desc_output.stdout[0]
            fail_msg: "Ethernet2 description does not match the expected value"
            success_msg: "Compliance check passed"
    ```

2. Run it, it should fail on both hosts becuase your latest description change does not match.

    ```bash
    ansible-playbook -i inventory.yml compliance_check.yml
    ```
3. Confirm the play fails with your `fail_msg`, clearly naming what went wrong, rather than a generic error.

4. Restore the interface descriptions to "Link to srl1" either manually or using Ansible as in Task 11.

5. Run the compliance check again. It should pass.


### Questions and Deliverables

1. Provide the failing output from step 2 and the passing output from step 4.
2. Why is a check like this, run automatically after every change, more reliable than a person periodically reading through show run by eye?

## Task 13: Enabling OSPF with Ansible

Objective: push a routing configuration and confirm with a ping that it actually changed what each device can reach.

1. Add a `router_id` to each host in your inventory. Keep everything else the same.

    ```bash
    nano inventory.yml
    ```

    ```yaml
    all:
      children:
        ceos:
          hosts:
            ceos1:
              ansible_host: ceos1
              router_id: 10.255.0.1
            ceos2:
              ansible_host: ceos2
              router_id: 10.255.0.2
          vars:
            # no change
    ```

2. Create the template. IP routing is disabled by default on cEOS, that has to be turned on globally before OSPF can do anything, no matter what else is configured.

    ```bash
    nano templates/ospf.j2
    ```

    ```jinja
    ip routing
    !
    interface Ethernet1
      ip ospf area 0.0.0.0
    !
    interface Ethernet2
      ip ospf area 0.0.0.0
    !
    router ospf 100
      router-id {{ router_id }}
      passive-interface default
      no passive-interface Ethernet1
      no passive-interface Ethernet2
      max-lsa 12000
    ```

    passive-interface default followed by two no passive-interface lines is a defensive pattern, every interface starts passive, and only the two you explicitly reactivate will ever form an adjacency, rather than relying only on which interfaces happen to have ip ospf area set.

3. Create the playbook.

    ```bash
    nano configure_ospf.yml
    ```

    ```yaml
    ---
    - name: Enable OSPF
      hosts: ceos
      gather_facts: false
      tasks:
        - name: Apply templated OSPF configuration
          arista.eos.eos_config:
            content: "{{ lookup('ansible.builtin.template', 'templates/ospf.j2') }}"
    ```

4. Run it.

    ```bash
    ansible-playbook -i inventory.yml configure_ospf.yml
    ```

5. Verify adjacencies formed, from either cEOS node.

    ```bash
    ansible -i inventory.yml ceos -m arista.eos.eos_command -a "commands='show ip ospf neighbor'"
    ```

    You should see both ceos1, 10.255.0.1, and srl1, 10.255.0.3, listed as FULL.

6. Confirm OSPF actually learned something the nodes didn't already have a route to.

    ```bash
    ansible -i inventory.yml ceos -m arista.eos.eos_command -a "commands='show ip route ospf'"
    ```

7. Prove it with two traceroute, from `ceos1` and `ceos2` to a remote subnet.

    ```bash
    docker exec -it ceos1 Cli -c "traceroute 10.0.23.2"
    docker exec -it ceos2 Cli -c "traceroute 10.0.13.1"
    ```

    Both should succeed by going through a transit subnet.

    Note: You can use Ansible ad hoc command in this step. Remember to specify which node you want to use, otherwise the command will be execute in all nodes in the inventory.

    ```bashn
    ansible -i inventory.yml ceos1 -m arista.eos.eos_command -a "commands='traceroute 10.0.23.2'"  
    ```

### Questions and Deliverables

1. Provide the outputs from steps 5, 6, and 7.

## Task 14: Committing Your Work

Objective: bring this lab's files into your existing repository.

1. Move to the root of your repository and check files that need to be added.

    ```bash
    cd ~/labs
    git status
    ```

3. Stage and confirm what is about to be committed.

    ```bash
    git add lab4 requirements.txt
    git status
    ```

4. Commit and push.

    ```bash
    git commit -m "Add Lab 4 gNMI telemetry, gNMI Set, and Ansible OSPF automation"
    git push
    ```

### Questions and Deliverables

1. Provide the output of `git status` from step 3.
2. Provide the output of `git log --oneline -5` after your commit.

# Clean Up

Save the running configuration on every node, then destroy the topology. The saved state needs the generated lab directory to still exist for the next lab's redeploy.

```bash
sudo containerlab save -t ~/labs/topology/lab-net.clab.yml
sudo containerlab destroy -t ~/labs/topology/lab-net.clab.yml
```

If you want to confirm the save actually captured OSPF before destroying anything, `ceos1`'s and `srl1`'s saved startup configs are readable directly:

```bash
cat ~/labs/topology/clab-lab-net/ceos1/flash/startup-config
cat ~/labs/topology/clab-lab-net/srl1/config/config.json
```

Deactivate your virtual environment when you're done.

```bash
deactivate
```

# Submission

Confirm your repository includes, at minimum, the following, then submit as instructed by your course delivery platform:

- lab4/scripts/ files
- lab4/ansible/inventory.yml
- lab4/ansible/templates files
- lab4/ansible/ files 
- requirements.txt
- Your answers to the Questions and Deliverables sections, submitted as your lab report per your instructor's separate instructions


\newpage

# Appendix: Command Summary

## gNMI Tools

| Command | Usage |
|---|-----|
| python3 gnmi_tool.py <host> modules | Print the models a device advertises over gNMI |
| python3 gnmi_tool.py <host> config <path> | Retrieve a configuration snapshot with Get |

## pygnmi

| Call | Usage |
|---|-----|
| gNMIclient(**params) | Open a gNMI session using parameters from devices.yaml |
| gc.subscribe(subscribe=<dict>) | Open a Subscribe stream, returns an iterator of responses |
| telemetryParser(response) | Convert a raw Subscribe response into a plain dict |
| gc.set(update=[(path, value), ...]) | Merge a value into an existing configuration at path, without disturbing siblings |
| gc.set(replace=[(path, value), ...]) | Replace everything at path with value, removing anything not included |

## Ansible

| Command | Usage |
|---|-----|
| ansible-galaxy collection install <collection> | Install a collection not bundled with ansible-core |
| ansible-galaxy collection list | List installed collections |
| ansible -i \<inventory\> \<group\> -m <module> -a "<args>" | Run a single ad hoc module against a group |
| ansible-playbook -i \<inventory\> \<playbook\>.yml | Run a playbook |
| ansible-playbook ... --check | Preview changes without applying them |
| ansible-playbook ... --check --diff | Preview changes and show exactly what would differ |

## OSPF Addressing

| Node | Router ID | Loopback |
|---|---|---|
| ceos1 | 10.255.0.1 | none |
| ceos2 | 10.255.0.2 | none |
| srl1 | 10.255.0.3 | system0, 10.255.0.3/32 |

## Default Credentials

| Kind | Username | Password |
|---|---|---|
| Arista cEOS | admin | admin |
| Nokia SR Linux | admin | NokiaSrl1! |

# Appendix: Node Configuration

Copy and paste the configuration below into each network node.

## ceos1

```
interface Ethernet1
   no switchport
   ip address 10.0.12.1/30
!
interface Ethernet2
   no switchport
   ip address 10.0.13.2/30
!
end
```

## ceos2

```
interface Ethernet1
   no switchport
   ip address 10.0.12.2/30
!
interface Ethernet2
   description Link to srl1
   no switchport
   ip address 10.0.23.1/30
!
end
```

## srl1

<!--
info flat | filter interface
info flat | filter network-instance
-->

```
set / interface ethernet-1/1 admin-state enable
set / interface ethernet-1/1 subinterface 0 ipv4 admin-state enable
set / interface ethernet-1/1 subinterface 0 ipv4 address 10.0.23.2/30
set / interface ethernet-1/2 admin-state enable
set / interface ethernet-1/2 subinterface 0 ipv4 admin-state enable
set / interface ethernet-1/2 subinterface 0 ipv4 address 10.0.13.1/30
set / network-instance default interface ethernet-1/1.0
set / network-instance default interface ethernet-1/2.0
```