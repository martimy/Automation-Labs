---
title: Lab 3
subtitle: Data Modeling and NETCONF Automation
highlight-style: tango
toc: true
output:
  pdf_document:
    highlight: custom-tango.theme # option: tango, pygments, kate, monochrome, espresso, haddock, breezedark
    toc_depth: 2
geometry: margin=1in
---

\newpage

# Introduction

This lab covers material from Lecture 5 and Lecture 6. You will spend the first part of the lab working with data formats and YANG outside of any live device, converting a small dataset between JSON and YAML, reading an RFC 8340 tree diagram, and using pyang to catch errors in a YANG module before you would ever trust it against real hardware. In the second part, you will point NETCONF tools at the ring topology from Lab 2, srl1 in particular, discover what it supports, read a real configuration payload back off the wire, and then write your own short script using ncclient to edit and commit a change through its candidate datastore.

This lab starts by redeploying your Lab 2 ring from its saved state, see Task 0. If Lab 2's interface configuration doesn't come back with it, redeploy and reconfigure it using Lab 2 Tasks 3 and 4 before continuing.

RESTCONF is not covered hands on in this lab. Arista supports it, but only after a certificate and an access control change that add real setup time without teaching anything NETCONF hasn't already covered, and Nokia SR Linux does not implement it at all, offering JSON-RPC in its place. It stays a short conceptual question instead of a task.

srl1 carries the heavy NETCONF and YANG work in this lab, consistent with how Lab 2 scoped things, heavy CLI use on Arista, heavy YANG use on Nokia. ceos1 and ceos2 show up mainly for comparison.

# Lab Objectives

By the end of this lab, you will be able to:

1. Convert a small dataset between JSON and YAML using Python's json and yaml libraries
2. Read an RFC 8340 YANG tree diagram and identify configuration versus operational state nodes
3. Use pyang to catch structural and syntax errors in a YANG module before trusting it against a real device
4. Verify NETCONF reachability on a network device before scripting against it
5. Discover a device's supported NETCONF capabilities and YANG modules, and pull a YANG schema directly off a live device
6. Read a real NETCONF configuration payload and connect it back to the module that defines it, including vendor augmentation
7. Write a Python script using ncclient to edit and commit a configuration change through a device's candidate datastore

# Lab Environment and Preparation

You will need:

- Your Lab 2 ring, redeployed from its saved state in Task 0, with ceos1, ceos2, and srl1 carrying their Lab 2 interface addressing
- Your GitHub Classroom repository, cloned and up to date on this VM, now containing labs/lab1 and labs/lab2
- pyang already installed on your VM
- Your instructor's tools repository, https://github.com/martimy/netconf-gnmi-tools, containing nc_wrapper.sh, netconf_tool.py, devicelib.py, and devices.yaml

NETCONF runs on TCP port 830 on both cEOS and SR Linux in this topology, and both come with it enabled by default.

\newpage

# Part A: Data Formats and YANG, Off the Device

## Task 0: Environment Check and Tooling Setup

Objective: Start the topology created in Lab2, set up this lab's folder structure and virtual environment, and download some NETCONF tools.

1. Start the Containerlab topology.

    ```bash
    sudo containerlab deploy -t ~/labs/lab2/topology/lab2-ring.clab.yml
    ```

    If you receive a message about containers already exist (perhaps because the topology was not destroyed in the previous lab session), inspect the topology to confirm:

    ```bash
    sudo containerlab inspect -t ~/labs/lab2/topology/lab2-ring.clab.yml
    ```    

    You should see all three nodes running. If this task fails, redeploy and reconfigure the topology using Lab 2 Tasks 3 and 4 before continuing.

2. Create this lab's folder structure.

    ```bash
    mkdir -p ~/labs/lab3/data ~/labs/lab3/yang ~/labs/lab3/scripts
    cd ~/labs/lab3
    ```

3. Create and activate a virtual environment for this lab.

    ```bash
    python3 -m venv .velab3
    source .velab3/bin/activate
    ```

4. Clone the tools repository outside this repository entirely, so it never becomes a nested git repository inside your own.

    ```bash
    cd ~
    git clone https://github.com/martimy/netconf-gnmi-tools tools
    ```

5. Copy the files this lab uses into your own lab3/scripts folder and confirm that `nc_wrapper.sh` is executable.

    ```bash
    cp ~/tools/nc_wrapper.sh ~/tools/netconf_tool.py \
    ~/tools/devicelib.py ~/tools/devices.yaml ~/labs/lab3/scripts/
    ls -l ~/labs/lab3/scripts
    ```

6. Check both files against this topology's node names, ceos1, ceos2, and srl1. `nc_wrapper.sh` already matches, no edit needed there. `devices.yaml` does not, compare its device entries against `nc_wrapper.sh`'s CREDENTIALS list, find what's wrong, and fix it.

7. Install the packages this lab needs, then freeze the exact versions into your own repository.

    ```bash
    cd ~/labs/lab3
    pip install -r ~/tools/requirements.txt
    pip freeze > requirements.txt
    ```

8. Confirm the key tools are available.

    ```bash
    pyang --version
    netconf-console2 --help | head -5
    ```

### Questions and Deliverables

1. Provide the output of Step 8 above.
2. What was wrong with devices.yaml before you fixed it, and how did you find it? Confirm your fix by running `python3 netconf_tool.py ceos2 capabilities` successfully.

## Task 1: Converting Data Between JSON and YAML

Objective: convert a small VLAN list between JSON and YAML using Python, and notice what format alone can and cannot guarantee about the data inside it.

1. Create the script.

    ```bash
    nano scripts/convert_vlans.py
    ```

    ```python
    import json
    import yaml

    vlans = [
        {"id": 10, "name": "USERS"},
        {"id": 20, "name": "VOICE"},
        {"id": 99, "name": "MGMT"},
    ]

    print("--- JSON ---")
    print(json.dumps(vlans, indent=2))

    print("--- YAML ---")
    print(yaml.dump(vlans, sort_keys=False))

    with open("data/vlans.yaml", "w") as f:
        yaml.dump(vlans, f, sort_keys=False)

    with open("data/vlans.yaml") as f:
        loaded = yaml.safe_load(f)

    assert loaded == vlans
    print("Round trip successful")
    ```

2. Run it.

    ```bash
    python scripts/convert_vlans.py
    ```

3. Confirm data/vlans.yaml was written, and that the round trip assertion passed rather than raising an error.

### Questions and Deliverables

1. Provide the JSON and YAML output from step 2.
2. Nothing in this script or in either file stops you from typing an invalid VLAN id of 5000. What needs to be done  to catch that mistake, and which part of this course covers it?

## Task 2: Reading a YANG Tree with pyang

Objective: use `pyang` to visualize the standard ietf-interfaces module and identify configuration versus operational state nodes using RFC 8340 tree notation.

1. Download the module.

    ```bash
    cd ~/labs/lab3/yang   
    git clone https://github.com/YangModels/yang ietf
    cp ietf/standard/ietf/RFC/ietf-interfaces.yang .
    ```

    <!-- could not download the individual files -->

2. Generate the tree.

    ```bash
    pyang -f tree ietf-interfaces.yang
    ```

    <!-- the tree prints fine without any errors even if the entire ietf folder is removed -->
    <!-- so we could ask students to get the file for the device instead of cloning the entire repo -->

3. Read the output. Find a node marked `rw`, and one marked `ro`, and find the interfaces list's key.

### Questions and Deliverables

1. Provide the tree output from step 2.
2. Pick one `rw` node and one `ro` node from the tree. What does that marker tell you about whether a NETCONF client is allowed to write to it?
3. What does `pyang`'s tree notation use to show that the interface list is keyed by name?


## Task 3: Validating a YANG Module with pyang

Objective: use `pyang` to catch structural and syntax errors in a small module before you would ever trust it against a real device. You are validating a module here, not authoring one from a blank file, that is a deeper skill than most network engineers need day to day.

1. Create the following file exactly as shown, it has two deliberate errors in it.

    ```bash
    cd ~/labs/lab3/yang
    nano example-vlans.yang
    ```

    ```yang
    module example-vlans {
      namespace "urn:example:vlans";
      prefix vl;

      container vlans {
        list vlan {
          leaf id {
          }
          leaf name {
            type string;
          }
        }
      }
    }
    ```

2. Validate it, and record what pyang reports.

    ```bash
    pyang example-vlans.yang
    ```

3. Fix the first error `pyang` reports, then run the same command again. Confirm the second error is still there.

4. Fix the second error as well, then validate one more time. A clean pass produces no output at all.

    ```bash
    pyang example-vlans.yang
    ```

5. Generate a tree of your now-valid module, to confirm it looks the way you intended.

    ```bash
    pyang -f tree example-vlans.yang
    ```

### Questions and Deliverables

1. Provide the exact error output from step 2, before either fix.
2. Provide your fixed example-vlans.yang, and the tree output from step 5.
3. Why does a list need a key statement in YANG? What would be ambiguous about the vlan list without one?


\newpage

# Part B: NETCONF on the Ring

## Task 4: Verifying NETCONF Reachability

Objective: confirm NETCONF is actually listening before you point any tooling at it, the same instinct you already applied to Docker and Containerlab back in Lab 2.

1. Check the raw NETCONF subsystem directly over SSH. This dumps the server's hello message, its capabilities, then hangs, press Ctrl+C once you've seen it.

    ```bash
    ssh -p 830 admin@srl1 -s netconf
    ```

2. Repeat the same check against ceos1.

    ```bash
    ssh -p 830 admin@ceos1 -s netconf
    ```

3. Now use `nc_wrapper.sh` to do the same thing more cleanly.

    ```bash
    cd ~/labs/lab3/scripts
    ./nc_wrapper.sh srl1 --hello
    ./nc_wrapper.sh ceos1 --hello
    ```

### Questions and Deliverables

1. Provide the capability list from the `--hello` output for `srl1` and for `ceos1`.
2. Both outputs list a set of URNs under `urn:ietf:params:netconf:capability`. Use `grep` to filter these URNs then pick one you recognize from the lectures and explain what it tells a client about what the server supports.

## Task 5: Discovering Capabilities, Modules, and a Live Schema

Objective: use `netconf_tool.py` to see what `srl1` actually supports, rather than assuming it matches the standard module you read in Task 2.

1. List `srl1`'s capabilities.

    ```bash
    cd ~/labs/lab3/scripts
    python3 netconf_tool.py srl1 capabilities
    ```

2. List the YANG modules `srl1` advertises.

    ```bash
    python3 netconf_tool.py srl1 modules
    ```

3. Search that output for an interfaces related module. Do you see `ietf-interfaces`? You're looking for the exact module actually used for configuration, not just any name containing interfaces, SR Linux advertises several `openconfig-if-*` submodules alongside it, focus on the one named plainly `openconfig-interfaces`.

    ```bash
    python3 netconf_tool.py srl1 modules | grep -i interfaces
    ```

4. Pull that module's schema directly off the live device, rather than downloading it from anywhere.

    ```bash
    python3 netconf_tool.py srl1 schema <module-name-from-step-3>
    ```

    This saves a `.yang` file into your current directory. Move it into your yang folder.

    ```bash
    mv <module-name-from-step-3>.yang ~/labs/lab3/yang/
    ```

    <!-- Answer: python3 netconf_tool.py srl1 schema openconfig-interfaces -->

5. Generate a tree of the module you just pulled. This module imports several other OpenConfig modules you haven't downloaded, so `pyang` needs to be told to tolerate the unresolved imports rather than fail on them.

    ```bash
    pyang -f tree ~/labs/lab3/yang/<module-name-from-step-3>.yang --ignore-errors
    ```

### Questions and Deliverables

1. Which interfaces related module did `srl1` actually advertise in step 3? Is it the standard `ietf-interfaces` module from Task 2, or something else?
2. Provide the tree output from step 5.


## Task 6: From CLI Configuration to a Real NETCONF Payload

Objective: configure one small, new piece of state through the CLI you already know from Lab 2, then read its real NETCONF representation back off the wire, rather than only ever hand building payloads from a bare tree.

Lab 2 configured IP addressing on every interface in this ring but never touched interface descriptions. That gap is what this task fills in.

1. On srl1, set a description on the ethernet-1/2 interface, the link to ceos1.

    ```bash
    ssh admin@srl1
    ```

    ```text
    enter candidate
    set / interface ethernet-1/2 description "Link to ceos1"
    diff
    commit now
    quit
    ```

2. Pull the interfaces portion of the running configuration over NETCONF and save it, rather than trying to filter for just this one interface.

    ```bash
    cd ~/labs/lab3/scripts
    ./nc_wrapper.sh srl1 --get-config \
    --filter /interfaces > ~/labs/lab3/data/srl1-interfaces.xml
    ```

3. Search the saved file for the interface and description you just configured.

    ```bash
    grep -B2 -A10 "ethernet-1/2" ~/labs/lab3/data/srl1-interfaces.xml
    ```

4. Look at the namespace declared on the enclosing element in that output, this tells you which YANG module actually owns this data on the wire.

### Questions and Deliverables

1. Provide the grep output from step 3, including the namespace declaration on the enclosing element.
2. Was the module that owns this data the same one you pulled the schema for in Task 5, or a different one? What does that tell you about how much a vendor can add on top of a standard or OpenConfig model through augmentation?

<!--
The model is <type xmlns:iana-if-type="urn:ietf:params:xml:ns:yang:iana-if-type">iana-if-type:ethernetCsmacd</type>
-->

## Task 7: Writing Your Own NETCONF Automation Script

Objective: write a short `ncclient` script that edits and commits a configuration change on `srl1`'s candidate datastore, using the real payload structure you found in Task 6 as your template, rather than a structure someone hands you.

1. Open `data/srl1-interfaces.xml` and copy the exact XML element for the `ethernet-1/1` interface including the `<interface>...</interface>` tags.

2. Create the script, and paste your adapted element into the `config_snippet` variable. Add a new description `<description>...</description>` in similar location as the `grep` output of Step 3 in Task 6.

    ```bash
    nano ~/labs/lab3/scripts/edit_srl1.py
    ```

    ```python
    from ncclient import manager

    srl1 = {
        "host": "srl1",
        "port": 830,
        "username": "admin",
        "password": "NokiaSrl1!",
        "hostkey_verify": False,
    }

    # Paste your adapted element from Task 6 here, targeting ethernet-1/1
    # instead of ethernet-1/2, wrapped in a <config> element.
    config_snippet = """
    <config>

    </config>
    """

    with manager.connect(**srl1) as m:
        m.edit_config(target="candidate", config=config_snippet)
        m.commit()
        print("Change committed")
    ```

3. Run it.

    ```bash
    python edit_srl1.py
    ```

4. Verify the change landed, using the same technique from Task 6.

    ```bash
    cd ~/labs/lab3/scripts
    ./nc_wrapper.sh srl1 --get-config \
    --filter /interfaces > ~/labs/lab3/data/srl1-interfaces-after.xml
    grep -B2 -A10 "ethernet-1/1" ~/labs/lab3/data/srl1-interfaces-after.xml
    ```

5. Confirm your new description text appears.

### Questions and Deliverables

1. Provide your completed `edit_srl1.py`.
2. Provide the grep output from step 4, showing your new description in place.
3. edit_config was called with `target="candidate"`, not `target="running"`. Which command from Task 6's CLI session does the commit() call in your script correspond to, and what would you expect to happen if you called `m.edit_config` the same way but never called `m.commit()` at all?

## Task 8: Committing Your Work

Objective: bring this lab's files into your existing repository, and make sure neither the virtual environment nor your instructor's separate tools repository end up committed by accident.

1. Move to the root of your repository.

    ```bash
    cd ~/labs
    git status
    ```

2. Exclude the virtual environment.

    ```bash
    echo "lab3/.velab3" >> .gitignore
    echo "lab3/yang/ietf" >> .gitignore
    ```

3. Stage and confirm what is about to be committed.

    ```bash
    git add lab3 .gitignore
    git status
    ```

    Confirm `.velab3` and `ietf` do not appear, and confirm nothing from `~/tools` is listed, since that repository lives outside labs entirely and was never inside anything git add here could reach.

4. Commit and push.

    ```bash
    git commit -m "Add Lab 3 YANG and NETCONF work"
    git push
    ```

### Questions and Deliverables

1. Provide the output of git status from step 3.
2. Provide the output of git log --oneline -5 after your commit.

# Clean Up

Save the running configuration on every node, then destroy the topology.

```bash
sudo containerlab save -t ~/labs/lab2/topology/lab2-ring.clab.yml
sudo containerlab destroy -t ~/labs/lab2/topology/lab2-ring.clab.yml
```

Deactivate your virtual environment when you're done.

```bash
deactivate
```

# Submission

Confirm your repository includes, at minimum, the following, then submit as instructed by your course delivery platform:

- lab3/data/vlans.yaml
- lab3/yang/ietf-interfaces.yang, example-vlans.yang, and the schema you pulled in Task 5
- lab3/scripts/convert_vlans.py, edit_srl1.py, nc_wrapper.sh, netconf_tool.py, devicelib.py, and your fixed devices.yaml
- lab3/requirements.txt
- The updated .gitignore excluding lab3/.velab3 and lab3/yang/ietf
- Your answers to the Questions and Deliverables sections, submitted as your lab report per your instructor's separate instructions

```bash
git log --oneline --graph -10
```

\newpage

# Appendix: Command Summary

## pyang

| Command | Usage |
|---|-----|
| pyang --version | Confirm the installed pyang version |
| pyang <file>.yang | Validate a module, silent output means no errors |
| pyang -f tree <file>.yang | Generate an RFC 8340 style tree diagram for a module |
| pyang -f tree <file>.yang --ignore-errors | Generate a tree even when the module has unresolved imports |

## NETCONF Tools

| Command | Usage |
|---|-----|
| ssh -p 830 <user>@<host> -s netconf | Manually check the raw NETCONF subsystem and see the server's hello message |
| ./nc_wrapper.sh <host> --hello | Print a device's NETCONF capabilities |
| ./nc_wrapper.sh <host> --get-config | Retrieve the full running configuration |
| ./nc_wrapper.sh <host> --get-config --filter <path> | Retrieve just one part of the running configuration |
| python3 netconf_tool.py <host> capabilities | Print a device's NETCONF capabilities from Python |
| python3 netconf_tool.py <host> modules | Print the YANG modules a device advertises |
| python3 netconf_tool.py <host> schema <module> | Save a YANG module's schema to a local file |

## ncclient

| Call | Usage |
|---|-----|
| manager.connect(host=, port=, username=, password=, hostkey_verify=False) | Open a NETCONF session |
| m.get_config(source="running") | Retrieve the running configuration |
| m.edit_config(target="candidate", config=<xml>) | Apply a configuration change to the candidate datastore |
| m.commit() | Commit the candidate datastore to running |

## Python and Virtual Environments

| Command | Usage |
|---|-----|
| python3 -m venv .velab3 | Create a virtual environment |
| source .velab3/bin/activate | Activate a virtual environment |
| pip install -r requirements.txt | Install packages from a pinned list |
| pip freeze > requirements.txt | Record installed packages and their versions |

## Default Credentials

| Kind | Username | Password |
|---|---|---|
| Arista cEOS | admin | admin |
| Nokia SR Linux | admin | NokiaSrl1! |
