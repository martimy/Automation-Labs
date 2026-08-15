---
title: INWK6312 - Lab 3
subtitle: Data Modeling and NETCONF Automation
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

The first part of this lab covers working with data formats and YANG outside of any live device, and using pyang tool to catch errors in a YANG module before using it in real hardware. The second part covers using NETCONF tools to discover what a network device supports, read write a configuration payload.

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

- Your assigned Ubuntu VM IP address provided in Brightspace: ________________.
- Your network topology, redeployed from its saved state in Task 0, with nodes carrying their interface configuration
- Your GitHub Classroom repository
- pyang already installed on your VM
- The lab's tools repository, https://github.com/martimy/Automation-Labs

NETCONF runs on TCP port 830 on both cEOS and SR Linux in this topology, and both come with it enabled by default.

>## If Things Go Wrong
>- Never destroy `lab-net` with `--cleanup`. It deletes the saved configuration folder this lab's Task 0 relies on, and everything from Lab 2 onward would need to be reconfigured by hand.
>- If `pyang` reports an error you did not expect on a file you did not intend to change, check for stray whitespace or a missing closing brace introduced by copy-paste, not just the logic of the module itself.
>- If `ncclient` raises an XML or namespace related error, check the namespace (`xmlns=`) in your payload against the real payload you pulled from the device in Task 6, do not assume a namespace from a different vendor or a different lab applies here.
>- If you damage the VM itself, stop and contact your instructor rather than continuing to troubleshoot.

\newpage

# Part A: Data Formats and YANG, Off the Device

## Task 0: Environment Check and Tooling Setup

Objective: Copy and start the topology created in Lab2, set up this lab's folder structure and download some NETCONF tools.

1. If you forgot to destroy the topology in Lab 2, do this now, otherwise skip this step.

    ```bash
    sudo containerlab save -t ~/labs/lab2/topology/lab-net.clab.yml
    sudo containerlab destroy -t ~/labs/lab2/topology/lab-net.clab.yml
    ```

2. Copy the Containerlab topology and the auto-generated folder to `~/labs/topology`.

    ```bash
    cp ~/labs/lab2/topology/lab-net.clab.yml ~/labs/topology
    sudo cp ~/labs/lab2/topology/clab-lab-net ~/labs/topology
    ```

3. Deploy the topology from the new location. You should also confirm that the nodes still retain their configuration.

    ```bash
    sudo containerlab deploy -t ~/labs/topology/lab-net.clab.yml
    ```    

4. Clone the tools repository outside this lab's repository to keep them separate. These tools will be used in this and future labs.

    ```bash
    cd ~ && git clone https://github.com/martimy/Automation-Labs tools
    ```

    <!--future -->

    ```bash
    cd ~ && git clone -b tools --single-branch --depth=1 https://github.com/martimy/Automation-Labs tools
    ```

5. Copy the tools into your own labs/tools folder and confirm that `nc_wrapper.sh` is executable.

    ```bash
    cp ~/tools/* ~/labs/tools/.
    ls -l ~/labs/tools
    ```

6. Check files `nc_wrapper.sh` and `devices.yaml` against this topology's node names, `ceos1`, `ceos2`, and `srl1` and credentials to ensure matching. Correct if needed.

7. Activate Python virtual environment.

    ```bash
    cd ~/labs
    source .velab/bin/activate
    ```

8. Install the packages this lab needs, then freeze the exact versions into your own repository.

    ```bash
    pip install -r ~/tools/requirements.txt
    pip freeze > requirements.txt
    ```

9. Confirm the key tools are available.

    ```bash
    pyang --version
    netconf-console2 --help | head -5
    ```

10. Create this lab's folder structure.

    ```bash
    mkdir -p ~/labs/lab3/data ~/labs/lab3/yang ~/labs/lab3/scripts
    cd ~/labs/lab3
    ```

### Questions and Deliverables

1. Provide the file `requirements.txt`

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
    python3 scripts/convert_vlans.py
    ```

3. Confirm data/vlans.yaml was written, and that the round trip assertion passed rather than raising an error.

### Questions and Deliverables

1. Provide the JSON and YAML output from step 2.
2. Nothing in this script or in either file stops you from typing an invalid VLAN id of 5000. What needs to be done  to catch that mistake, and which part of this course covers it?

## Task 2: Reading a YANG Tree with pyang

Objective: use `pyang` to visualize the standard ietf-interfaces module and identify configuration versus operational state nodes using RFC 8340 tree notation.

1. Download the module.

    ```bash
    cd ~/labs/lab3/yang && git clone https://github.com/YangModels/yang ietf
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

Objective: use `pyang` to catch structural and syntax errors in a small module.

1. Create the following file exactly as shown, it has two deliberate errors in it.

    ```bash
    cd ~/labs/lab3/yang && nano example-vlans.yang
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

Objective: confirm NETCONF is enabled and listening on the network nodes.

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
    ~/labs/tools/nc_wrapper.sh srl1 --hello
    ~/labs/tools/nc_wrapper.sh ceos2 --hello
    ```

### Questions and Deliverables

1. Provide the capability list from the `--hello` output for `srl1` and for `ceos1`.
2. Both outputs list a set of URNs under `urn:ietf:params:netconf:capability`. Use `grep` to filter these URNs then pick one you recognize from the lectures and explain what it tells a client about what the server supports.

## Task 5: Discovering Capabilities, Modules, and a Live Schema

Objective: use `netconf_tool.py` to discover the capabilities of `srl1` and the YANG models it supports.

1. List `srl1`'s capabilities.

    ```bash
    cd ~/labs/tools
    ./netconf_tool.py srl1 capabilities
    ```

2. List the YANG modules `srl1` advertises.

    ```bash
    ./netconf_tool.py srl1 modules
    ```

3. Search the output for an interfaces' related module. Do you see `*-interfaces` modules are supported?

    ```bash
    ./netconf_tool.py srl1 modules | grep -i interfaces
    ```

4. Pull that native module's schema directly off the live device, rather than downloading it from anywhere.

    ```bash
    ./netconf_tool.py srl1 schema srl_nokia-interfaces
    ```

    This saves a `.yang` file into your current directory. Move it into your yang folder.

    ```bash
    mv srl_nokia-interfaces.yang ~/labs/lab3/yang/
    ```

5. Generate a tree of the module you just pulled. This module imports several other modules you haven't downloaded, so `pyang` needs to be told to tolerate the unresolved imports rather than fail on them.

    ```bash
    cd ~/labs/lab3/yang
    pyang -f tree srl_nokia-interfaces.yang --ignore-errors
    ```

6. The previous output is large; try again by limiting the depth of the tree.

    ```bash
    pyang -f tree srl_nokia-interfaces.yang --ignore-errors --tree-depth=2
    ```

### Questions and Deliverables

1. How many interfaces related module did `srl1` actually advertise in step 3?
2. Why does Nokia SR Linux support all three major module types IETF, OpenConfig, and Native?
3. Provide the tree output from step 6.


## Task 6: From CLI Configuration to a Real NETCONF Payload

Objective: configure one small, new piece of state through the CLI, then read its real NETCONF representation back.

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
    ~/labs/tools/nc_wrapper.sh srl1 --get-config \
    --filter /interfaces > ~/labs/lab3/data/srl1-interfaces.xml
    ```

3. Search the saved file for the interface and description you just configured.

    ```bash
    grep -B2 -A10 "ethernet-1/2" ~/labs/lab3/data/srl1-interfaces.xml
    ```

4. Look at the namespace declared at the tope of the returned configuration, this tells you which YANG module is actually used for the configuration.

    ```bash
    head ~/labs/lab3/data/srl1-interfaces.xml
    ```

### Questions and Deliverables

1. Provide the grep output from step 3.
2. Was the module that owns this data the same one you pulled the schema for in Task 5, or a different one? What does that tell you about how much a vendor can add on top of a standard or OpenConfig model through augmentation?


## Task 7: Writing Your Own NETCONF Automation Script

Objective: write a short `ncclient` script that edits and commits a configuration change on `srl1`'s candidate datastore, using the real payload structure you found in Task 6 as your template.

1. Open `~/labs/lab3/data/srl1-interfaces.xml` and copy the exact XML element for the `ethernet-1/1` interface enclosed within the `<interface>...</interface>` tags.

2. Create the script, and paste your adapted element into the `config_snippet` variable. Add a new description `<description>Link to ceos2</description>` in similar location as the output of Step 3 in Task 6.

    ```bash
    cd ~/labs/lab3/scripts && nano edit_srl1.py
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

    config_snippet = """
    <config xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
        <interfaces xmlns="http://openconfig.net/yang/interfaces">
            <interface>
                <name>ethernet-1/1</name>
            <config>
                <name>ethernet-1/1</name>
                <enabled>true</enabled>
                <description>Link to ceos2</description>
            </config>
            </interface>
        </interfaces>
    </config>
    """

    with manager.connect(**srl1) as m:
        m.edit_config(target="candidate", config=config_snippet)
        m.commit()
        print("Change committed")
    ```

3. Check it compiles, as you did in Lab 2, then run it.

    ```bash
    python3 -m py_compile edit_srl1.py
    python3 edit_srl1.py
    ```

4. Verify the change landed, using the same technique from Task 6.

    ```bash
    ~/labs/tools/nc_wrapper.sh srl1 --get-config \
    --filter /interfaces > ~/labs/lab3/data/srl1-interfaces-after.xml
    grep -B2 -A10 "ethernet-1/1" ~/labs/lab3/data/srl1-interfaces-after.xml
    ```

5. Confirm your new description text appears.

### Questions and Deliverables

1. Provide your completed `edit_srl1.py`.
2. Provide the grep output from step 4, showing your new description in place.
3. edit_config was called with `target="candidate"`, not `target="running"`. Which command from Task 6's CLI session does the commit() call in your script correspond to, and what would you expect to happen if you called `m.edit_config` the same way but never called `m.commit()` at all?

## Task 8: Committing Your Work

Objective: bring this lab's files into your existing repository, excluding the downloaded ietf's YANG modules.

1. Move to the root of your repository.

    ```bash
    cd ~/labs
    git status
    ```

2. Exclude the `ietf` folder.

    ```bash
    echo "lab3/yang/ietf" >> .gitignore
    ```

3. Stage and confirm what is about to be committed.

    ```bash
    git add lab3 tools topology requirements.txt .gitignore
    git status
    ```

    Confirm `ietf` is not listed. Are there files not tracked yet? Use `restore --staged <file>` to untrack any files that you do not want to commit.

4. Commit and push.

    ```bash
    git commit -m "Add Lab 3 YANG and NETCONF work"
    git push
    ```

5. Tag this checkpoint.

    ```bash
    git tag lab3-complete
    ```

### Questions and Deliverables

1. Provide the output of git status from step 3.
2. Provide the output of `git log --oneline -5` after your commit.

# Clean Up

Save the running configuration on every node, then destroy the topology.

```bash
sudo containerlab save -t ~/labs/topology/lab-net.clab.yml
sudo containerlab destroy -t ~/labs/topology/lab-net.clab.yml
```

Deactivate your virtual environment when you're done.

```bash
deactivate
```

# Submission

Confirm your repository includes, at minimum, the following, then submit as instructed by your course delivery platform:

- lab3/data/ files
- lab3/yang/ files
- lab3/scripts/ files
- requirements.txt
- The updated .gitignore
- Your answers to the Questions and Deliverables sections, submitted as your lab report per your instructor's separate instructions


\newpage

# Appendix: Command Summary

## pyang

| Command | Usage |
|---|---|
| pyang --version | Confirm the installed pyang version |
| pyang \<file\>.yang | Validate a module, silent output means no errors |
| pyang -f tree \<file\>.yang | Generate an RFC 8340 style tree diagram for a module |
| pyang -f tree \<file\>.yang --ignore-errors | Generate a tree even when the module has unresolved imports |

## NETCONF Tools

| Command | Usage |
|---|---|
| ssh -p 830 <user>@<host> -s netconf | Manually check the raw NETCONF subsystem and see the server's hello message |
| ./nc_wrapper.sh \<host\> --hello | Print a device's NETCONF capabilities |
| ./nc_wrapper.sh \<host\> --get-config | Retrieve the full running configuration |
| ./nc_wrapper.sh \<host\> --get-config --filter <path> | Retrieve just one part of the running configuration |
| python3 netconf_tool.py \<host\> capabilities | Print a device's NETCONF capabilities from Python |
| python3 netconf_tool.py \<host\> modules | Print the YANG modules a device advertises |
| python3 netconf_tool.py \<host\> schema <module> | Save a YANG module's schema to a local file |

## ncclient

| Call | Usage |
|---|---|
| manager.connect(host=, port=, username=, password=, hostkey_verify=False) | Open a NETCONF session |
| m.get_config(source="running") | Retrieve the running configuration |
| m.edit_config(target="candidate", config=<xml>) | Apply a configuration change to the candidate datastore |
| m.commit() | Commit the candidate datastore to running |

## Python and Virtual Environments

| Command | Usage |
|---|---|
| source .velab/bin/activate | Activate a virtual environment |
| pip install -r requirements.txt | Install packages from a pinned list |
| pip freeze > requirements.txt | Record installed packages and their versions |

## Default Credentials

| Kind | Username | Password |
|---|---|---|
| Arista cEOS | admin | admin |
| Nokia SR Linux | admin | NokiaSrl1! |
