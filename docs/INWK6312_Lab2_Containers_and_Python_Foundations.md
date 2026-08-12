---
title: Lab 2
subtitle: Containers, Network Emulation, and Python Automation Foundations
highlight-style: tango
toc: true
output:
    pdf_document:
        toc_depth: 2
        highlight: custom-tango.theme # option: tango, pygments, kate, monochrome, espresso, haddock, breezedark
geometry: margin=1in
---

\newpage

# Introduction

This lab covers Docker then use Containerlab to deploy a small mixed vendor topology, two Arista cEOS nodes and one Nokia SR Linux node, connected in a ring. You will bring up Layer 3 reachability on that topology by hand, using each vendor's own CLI. In the second part of the lab, you will build an isolated Python environment and use Netmiko to talk to the Arista nodes over SSH instead of typing commands yourself, parse the CLI output you get back, and handle a connection failure with a custom exception instead of letting the script crash.

This lab continues in the same repository you created in Lab 1. Your local folder for that repository is still named `~/labs`, that name refers to the repository itself, not to this specific lab, you will simply add a new `lab2` folder inside it.

<!--
The Nokia SR Linux node is present in this lab mainly to establish the topology mechanics. You will bring its interfaces up so the topology is fully reachable, but you will not push it hard on the CLI or YANG side yet, that comes later once the course reaches NETCONF, RESTCONF, and native YANG modeling.
-->

# Lab Objectives

By the end of this lab, you will be able to:

1. Inspect Docker images and containers to explain the difference between an image and a running container
2. Explain the components of a Containerlab topology definition file, including kinds, nodes, images, and links
3. Deploy a multi vendor topology combining Arista cEOS and Nokia SR Linux nodes
4. Manually configure Layer 3 interfaces on both Arista EOS and Nokia SR Linux, and confirm reachability across a fully meshed topology
5. Create and use an isolated Python virtual environment to manage a project's dependencies
6. Use Netmiko to connect to a network device over SSH and retrieve CLI output
7. Parse unstructured CLI output using a regular expression with named groups
8. Design and raise a custom exception class so a multi device script can report a connection failure without crashing

# Lab Environment and Preparation

You will need:

- Your assigned Ubuntu VM, with Docker, Containerlab, and Python 3 with the venv module preinstalled
- The `ceos:v4.36` and `ghcr.io/nokia/srlinux:26.7.1-554-amd64` images already pulled and available locally, confirm this in Task 0
- Your GitHub Classroom repository from Lab 1, cloned and up to date on this VM

If any of the tools or images above are missing when you reach that step, check with your lab instructor before trying to install or pull anything yourself.

Containerlab operations in this lab require sudo, since they create network namespaces and manage Docker on your behalf. Commands that need it are shown with sudo, if a command does not show sudo, you should not need it.

Note that both the cEOS and SR Linux images ship with a default login account already configured, and Containerlab automatically registers each deployed node's hostname in your VM's own /etc/hosts file, so you can reach a node by name instead of hunting down its management IP address.

\newpage

# Part A: Containers and Network Emulation

## Task 0: Docker Environment Review

Objective: confirm your environment is ready and connect what Lecture 4 covered about images, layers, and containers to what is actually sitting on your VM. This is a review, you will not build or modify any images in this task.

1. Confirm Docker is available and check the version[^docker].

    ```bash
    docker --version
    ```

2. List the images already on your VM.

    ```bash
    docker image ls
    ```

    You should see `ceos:v4.36` and `ghcr.io/nokia/srlinux:26.7.1-554-amd64` in the list, alongside any other preloaded images.

3. Inspect the metadata of each image this lab will use. An image is an immutable snapshot, this pulls out just its creation date and size rather than the entire JSON blob.

    ```bash
    docker image inspect ceos:v4.36 --format 'Created: {{.Created}}\nSize: {{.Size}} bytes'
    docker image inspect ghcr.io/nokia/srlinux:26.7.1-554-amd64 --format 'Created: {{.Created}}\nSize: {{.Size}} bytes'
    ```

4. Review Docker's own storage summary, this reflects the layered, shared storage model (covered on Lecture 4).

    ```bash
    docker system df
    ```

5. Confirm Containerlab is installed and check its version.

    ```bash
    containerlab version
    ```

[^docker]: This lab was tested using v29.7.1.

### Questions and Deliverables

1. Compare the Size field for ceos:v4.36 and the SR Linux image from step 3. Which one is larger, and does that match the DISK USAGE or CONTENT SIZE columns you would see in a full docker image ls output?
2. In your own words, why does an image stay the same, unchanged object no matter how many containers you create from it?

## Task 1: Your First Containerlab Node, Arista cEOS

Objective: deploy a single cEOS node on its own, connect to its CLI, and destroy it, before combining anything with anything else.

1. Create the folder structure this lab will use.

    ```bash
    mkdir -p ~/labs/lab2/topology
    mkdir -p ~/labs/lab2/scripts
    cd ~/labs/lab2/topology
    ```

2. Create a small throwaway topology file with a single cEOS node.

    ```bash
    nano test-ceos.clab.yml
    ```

    ```yaml
    name: test-ceos
    topology:
      nodes:
        ceos1:
          kind: arista_ceos
          image: ceos:v4.36
    ```

3. Deploy it.

    ```bash
    sudo containerlab deploy -t test-ceos.clab.yml
    ```

4. Verify it came up and note its management IP address.

    ```bash
    sudo containerlab inspect -t test-ceos.clab.yml
    ```

5. Connect directly to its CLI. Containerlab names the underlying container `clab-<lab-name>-<node-name>`, so this node is `clab-test-ceos-ceos1`.

    ```bash
    sudo docker exec -it clab-test-ceos-ceos1 Cli
    ```

    You can also login via SSH using default username/password=`admin/admin` (recommnded):

    ```bash
    ssh admin@clab-test-ceos-ceos1
    ```

6. From the EOS prompt, run two read only commands, then leave the CLI.

    ```text
    show version
    show interfaces status
    exit
    ```

7. Destroy the lab, you are done with this throwaway topology.

    ```bash
    sudo containerlab destroy -t test-ceos.clab.yml --cleanup
    ```

The local `--cleanup` flag instructs containerlab to remove the auto-generated lab directory `clab-<lab-name>` and all its content. This prevents Containerlab from reusing previous startup configuration artifacts on the next deploy. In this case, you will not need any saved information.

### Questions and Deliverables

1. Provide the output of containerlab inspect from step 4.
2. What EOS software version did show version report inside your container?
3. Which interface did the `show interfaces` command list?

## Task 2: Adding Nokia SR Linux

Objective: deploy a single SR Linux node on its own, and get a first look at how its command structure differs from EOS, before destroying it.

1. Create a second throwaway topology file.

    ```bash
    cd ~/labs/lab2/topology
    nano test-srl.clab.yml
    ```

    ```yaml
    name: test-srl
    topology:
      nodes:
        srl1:
          kind: nokia_srlinux
          image: ghcr.io/nokia/srlinux:26.7.1-554-amd64
          type: ixr-d1
    ```

2. Deploy it and inspect it.

    ```bash
    sudo containerlab deploy -t test-srl.clab.yml
    sudo containerlab inspect -t test-srl.clab.yml
    ```

3. Connect to the SR Linux CLI. Note the command is `sr_cli`, not `Cli`.

    ```bash
    sudo docker exec -it clab-test-srl-srl1 sr_cli
    ```

    You can also login via SSH using default username/password=`admin/NokiaSrl1!` (recommnded):

    ```bash
    ssh admin@clab-test-srl-srl1
    ```

4. Run two read only commands, then leave the CLI.

    ```text
    show version
    show interface brief
    quit
    ```

5. Destroy the lab.

    ```bash
    sudo containerlab destroy -t test-srl.clab.yml --cleanup
    ```

### Questions and Deliverables

1. Provide the output of show version from the SR Linux CLI.
2. The SR Linux prompt looks like `--{ running }--[ ]--`, while the EOS prompt you saw in Task 1 was a plain hostname and symbol. What does the running portion of the SR Linux prompt tell you that the EOS prompt does not?
3. Which interface is up?

## Task 3: Building the Three Node Ring

Objective: combine both kinds into the persistent topology that carries forward into the rest of this course.

Three nodes connected in a ring means every node has a direct link to both of the other two, a ring of three is the same thing as a full mesh. This matters for what comes next, none of these nodes will need to forward traffic on behalf of another, unlike the router you built by hand out of namespaces in Lab 1.

1. Create the real topology file.

    ```bash
    cd ~/labs/lab2/topology
    nano lab2-ring.clab.yml
    ```

    ```yaml
    name: lab2-ring
    prefix: "" # Removes a prefix from the container names
    topology:
      nodes:
        ceos1:
          kind: arista_ceos
          image: ceos:v4.36
        ceos2:
          kind: arista_ceos
          image: ceos:v4.36
        srl1:
          kind: nokia_srlinux
          image: ghcr.io/nokia/srlinux:26.7.1-554-amd64
          type: ixr-d1
      links:
        - endpoints: ["ceos1:eth1", "ceos2:eth1"]
        - endpoints: ["ceos2:eth2", "srl1:ethernet-1/1"]
        - endpoints: ["srl1:ethernet-1/2", "ceos1:eth2"]
    ```

2. Deploy it.

    ```bash
    sudo containerlab deploy -t lab2-ring.clab.yml
    ```

3. Verify all three nodes are running.

    ```bash
    sudo containerlab inspect -t lab2-ring.clab.yml
    ```

4. Confirm Containerlab also registered each node's hostname on your VM. Because the topology file sets prefix to an empty string, the hostname it registers is the plain node name, not a clab prefixed version of it.

    ```bash
    cat /etc/hosts
    ```

    You should see a block bounded by CLAB-lab2-ring-START and CLAB-lab2-ring-END, mapping ceos1, ceos2, and srl1 to their management IP addresses. From this point on, you can reach any of the three nodes by name, ceos1, ceos2, or srl1, without needing to look up or type its management IP address.

5. Cross check from the Docker side as well.

    ```bash
    docker ps
    ```

6. Inspect the topology using the graph command.

    ```bash
    containerlab graph -t lab2-ring.clab.yml
    ```

### Questions and Deliverables

1. Provide the output of containerlab inspect -t lab2-ring.clab.yml.
2. Provide the block from /etc/hosts between the CLAB-lab2-ring-START and CLAB-lab2-ring-END markers.
3. Explain why the node names do not include the lab name prefix.

## Task 4: Configuring Layer 3 Reachability

Objective: bring up an IP address on each side of every link by hand, using each vendor's own CLI. Both cEOS and SR Linux already ship with a default login account, admin/admin on cEOS and admin/NokiaSrl1! on SR Linux, so Part B's Netmiko script will be able to authenticate without any extra setup here.

Addressing plan for this topology:

| Link | Node : Interface | IP Address |
|---|---|---|
| ceos1 $\leftrightarrow$ ceos2 | ceos1 : Ethernet1 | 10.0.12.1/30 |
| ceos1 $\leftrightarrow$ srl1 | ceos1 : Ethernet2 | 10.0.13.2/30 |
| ceos1 $\leftrightarrow$ ceos2 | ceos2 : Ethernet1 | 10.0.12.2/30 |
| ceos2 $\leftrightarrow$ srl1 | ceos2 : Ethernet2 | 10.0.23.1/30 |
| ceos2 $\leftrightarrow$ srl1 | srl1 : ethernet-1/1 | 10.0.23.2/30 |
| ceos1 $\leftrightarrow$ srl1 | srl1 : ethernet-1/2 | 10.0.13.1/30 |

Configure each node fully, and verify it, before moving to the next one. A typo in an address here looks like a broken link in Task 5, and is much harder to trace back once you are three nodes in.

1. Connect to ceos1.

    ```bash
    ssh admin@ceos1
    ```

2. Configure both of its data interfaces. On Arista EOS, a physical interface starts in switchport mode and must be explicitly converted to a routed port with no switchport before it will accept an IP address.

    ```text
    enable
    configure
    interface Ethernet1
       no switchport
       ip address 10.0.12.1/30
       no shutdown
    interface Ethernet2
       no switchport
       ip address 10.0.13.2/30
       no shutdown
    end
    ```

3. Verify before moving on.

    ```text
    show ip interface brief
    ```

    Both Ethernet1 and Ethernet2 should show your assigned addresses with a status and protocol of up. Then leave the CLI with exit.

4. Repeat the same pattern on ceos2, with its own addresses.

    ```bash
    ssh admin@ceos2
    ```

    ```text
    enable
    configure
    interface Ethernet1
       no switchport
       ip address 10.0.12.2/30
       no shutdown
    interface Ethernet2
       no switchport
       ip address 10.0.23.1/30
       no shutdown
    end
    show ip interface brief
    ```

5. Connect to srl1. SR Linux configuration happens inside a candidate datastore, which you commit explicitly, and a subinterface only forwards traffic once it is associated with a network instance.

    ```bash
    ssh admin@srl1
    ```

    ```text
    enter candidate
    set / interface ethernet-1/1 subinterface 0 ipv4 admin-state enable
    set / interface ethernet-1/1 subinterface 0 ipv4 address 10.0.23.2/30
    set / interface ethernet-1/2 subinterface 0 ipv4 admin-state enable
    set / interface ethernet-1/2 subinterface 0 ipv4 address 10.0.13.1/30
    set / network-instance default interface ethernet-1/1.0
    set / network-instance default interface ethernet-1/2.0
    ```

6. Verify before moving on.

    ```text
    diff
    ```

    Both ethernet-1/1 and ethernet-1/2 should show as up, with the addresses you just assigned. Also both interfaces should be assigned to the default network instance.

7. Commit and exit

    ```text
    commit now
    quit
    ```

    If commit is not sucessful, enter `discard stay` and repeat steps 5 to 7.


### Questions and Deliverables

1. Provide the show ip interface brief output from ceos1 and ceos2.
2. Provide the output of the `diff` command from srl1.


## Task 5: Verifying the Full Mesh

Objective: confirm every node can reach both of its neighbors directly.

1. From ceos1, ping both neighbors.

    ```text
    ping 10.0.12.2
    ping 10.0.13.1
    ```

2. From ceos2, ping both neighbors.

    ```text
    ping 10.0.12.1
    ping 10.0.23.2
    ```

3. From srl1, ping both neighbors. SR Linux requires the network instance to be specified on the ping command itself.

    ```text
    ping 10.0.23.1 network-instance default
    ping 10.0.13.2 network-instance default
    ```

### Questions and Deliverables

1. Provide the output of all six ping tests.


\newpage

# Part B: Python Foundations and Netmiko

## Task 6: Building an Isolated Python Environment

Objective: create a project specific virtual environment before installing anything, so this project's dependencies stay separate from the rest of the VM.

1. Move into your lab2 folder.

    ```bash
    cd ~/labs/lab2
    ```

2. Create and activate a virtual environment.

    ```bash
    python3 -m venv .velab2
    source .velab2/bin/activate
    ```

    Your prompt should now be prefixed with (.velab2).

3. Install Netmiko inside the environment.

    ```bash
    pip install netmiko
    ```

4. Freeze the installed dependencies to a file, so this environment is reproducible.

    ```bash
    pip freeze > requirements.txt
    cat requirements.txt
    ```

### Questions and Deliverables

1. Provide the contents of requirements.txt.
2. If a classmate cloned your repository onto their own VM and created a fresh virtual environment, what single pip command would recreate your exact environment from `requirements.txt`?

## Task 7: Your First Netmiko Connection

Objective: connect to ceos1 over SSH using Netmiko instead of docker exec, and pull the output of one command.

1. Make sure your virtual environment from Task 6 is still active, then create the script.

    ```bash
    nano scripts/connect_ceos1.py
    ```

    ```python
    from netmiko import ConnectHandler

    ceos1 = {
        "device_type": "arista_eos",
        "host": "ceos1",
        "username": "admin",
        "password": "admin",
    }

    connection = ConnectHandler(**ceos1)
    output = connection.send_command("show ip interface brief")
    print(output)
    connection.disconnect()
    ```

    This works because Containerlab added ceos1 to your VM's own /etc/hosts file when you deployed the topology in Task 3. You can also replace it with the node's management IP address from the containerlab inspect output, if you prefer.

2. Run it.

    ```bash
    python scripts/connect_ceos1.py
    ```

3. Verify the printed output matches what you saw directly on the CLI in Task 4, Netmiko is automating the same SSH session you could type by hand, it should show the same two interfaces and addresses.

### Questions and Deliverables

1. Provide the output of running this script.
2. The dictionary sets `device_type` to `arista_eos`. What does Netmiko use this value for internally?

## Task 8: Parsing CLI Output with Regular Expressions

Objective: turn the raw text from Task 7 into structured data your own code can use, instead of text a human has to read.

1. Create a new script that parses the output using a regex with named groups, the same pattern used in Lecture 3.

    ```bash
    nano scripts/parse_ceos1.py
    ```

    ```python
    import re
    from netmiko import ConnectHandler

    ceos1 = {
        "device_type": "arista_eos",
        "host": "ceos1",
        "username": "admin",
        "password": "admin",
    }

    connection = ConnectHandler(**ceos1)
    output = connection.send_command("show ip interface brief")
    connection.disconnect()

    pattern = r"(?P<interface>\S+)\s+(?P<ip>\d+\.\d+\.\d+\.\d+/\d+)\s+(?P<status>\S+)\s+(?P<protocol>\S+)"

    for match in re.finditer(pattern, output):
        print(match.group("interface"), match.group("ip"), match.group("status"))
    ```

2. Run it, and confirm it prints one line per interface that has an IP address, Ethernet1, Ethernet2, and Management1, correctly split into separate fields.

    ```bash
    python scripts/parse_ceos1.py
    ```

3. Add an if statement so the script only prints non-management interfaces whose status is up, without a change to the regex itself.

### Questions and Deliverables

1. Provide the output of the script from step 2.
2. Provide your modified code from step 3, and its output.

## Task 9: Handling Failures with a Custom Exception

Objective: extend the script to loop over both cEOS nodes, and make sure one unreachable device does not stop the script from checking the other.

1. Create the script.

    ```bash
    nano scripts/inventory_check.py
    ```

    ```python
    from netmiko import ConnectHandler, NetmikoTimeoutException, NetmikoAuthenticationException


    class DeviceConnectionError(Exception):
        """Raised when Netmiko cannot reach or authenticate to a device."""
        pass


    devices = [
        {"name": "ceos1", "device_type": "arista_eos", "host": "ceos1", "username": "admin", "password": "admin"},
        {"name": "ceos2", "device_type": "arista_eos", "host": "ceos2", "username": "admin", "password": "admin"},
    ]

    for device in devices:
        params = {key: value for key, value in device.items() if key != "name"}
        try:
            try:
                connection = ConnectHandler(**params)
            except (NetmikoTimeoutException, NetmikoAuthenticationException) as exc:
                raise DeviceConnectionError(f"Could not reach {device['name']}: {exc}") from exc
            output = connection.send_command("show ip interface brief")
            print(f"--- {device['name']} ---")
            print(output)
            connection.disconnect()
        except DeviceConnectionError as exc:
            print(f"Skipping {device['name']}: {exc}")
            continue
    ```

2. Run it, and confirm both devices report correctly.

    ```bash
    python scripts/inventory_check.py
    ```

3. Now deliberately break it. Change ceos1's host address in the devices list to something unreachable, such as 10.0.0.99, and run the script again.

    ```bash
    python scripts/inventory_check.py
    ```

4. Confirm the script prints a clear Skipping message for ceos1, naming it specifically, and still completes successfully for ceos2, rather than stopping on the first failure.

5. Restore ceos1's correct address before moving on.


### Questions and Deliverables

1. Provide the output from both the working run in step 2 and the deliberately broken run in step 3.
2. NetmikoTimeoutException and NetmikoAuthenticationException are caught specifically here, rather than a single bare except. Give one practical reason a script managing many devices would want to know which of these two happened, rather than only knowing that something failed.

## Task 10: Committing Your Work

Objective: bring the new topology file and scripts into your existing repository from Lab 1, continuing the same repository rather than starting a new one.

1. Move to the root of your repository.

    ```bash
    cd ~/labs
    git status
    ```

2. Make sure your virtual environment and the configuration directory created by containerlab are not committed, only requirements.txt should be tracked.

    ```bash
    echo "lab2/.velab2/" >> .gitignore
    echo "lab2/topology/clab-lab2-ring" >> .gitignore
    ```

3. Stage everything and confirm what is about to be committed.

    ```bash
    git add lab2 .gitignore
    git status
    ```

    Confirm `.velab2` and `clab-lab2-ring` do not appear anywhere in this output, only the topology file, scripts, requirements.txt, and the .gitignore change should be listed.
    
    Note: `git add` command is likely to produce a warning about adding embedded git repository if `lab2/topology/clab-lab2-ring` is not included in `.gitignore`.

4. Commit and push.

    ```bash
    git commit -m "Add Lab 2 ring topology and Netmiko automation scripts"
    git push
    ```

### Questions and Deliverables

1. Provide the output of git status from step 3, confirming what is excluded.
2. Provide the output of `git log --oneline -5` after your commit.

# Clean Up

You can destroy the lab now, but before that, you will need to save the device configurations to be reused in future labs. Typically, you would do that in each device individually using commands such as `write memory`, by containerlab offers a convenient way to to perform configuration save for all the containers running in a lab.

```bash
cd ~/labs/lab2/topology
sudo containerlab save -t lab2-ring.clab.yml
```

The `save` command will save the configuration files under the directory `lab2/topology/clab-lab2-ring`, which is not tracked by git.

Destroy the topology:

```bash
sudo containerlab destroy -t lab2-ring.clab.yml
```

Destroying and later redeploying this topology will bring the containers back and restore the topology with the saved configurations.

Deactivate the python virtual environment:

```bash
deactivate
```

# Submission

Confirm your repository includes, at minimum, the following, then submit as instructed by your course delivery platform:

- labs/lab2/topology/lab2-ring.clab.yml
- labs/lab2/scripts/connect_ceos1.py, parse_ceos1.py, and inventory_check.py
- labs/lab2/requirements.txt
- The updated .gitignore excluding lab2/.velab2/ and lab2/topology/clab-lab2-ring
- Your answers to the Questions and Deliverables sections, submitted as your lab report per your instructor's separate instructions

```bash
git log --oneline --graph -10
```

\newpage

# Appendix: Command Summary

## Containerlab

| Command | Usage |
|---|---|
| containerlab version | Confirm the installed Containerlab version |
| containerlab deploy -t <file>.clab.yml | Build a lab from its topology file |
| containerlab inspect -t <file>.clab.yml | Show running nodes and their management addresses |
| containerlab graph -t <file>.clab.yml | Visualize the topology defined in a topology file |
| containerlab save -t <file>.clab.yml | Saves configuration of all nodes in the generated lab directory |
| containerlab destroy -t <file>.clab.yml | Remove all nodes and links |
| containerlab destroy -t <file>.clab.yml --cleanup | Remove all nodes and links, and delete the generated lab directory |
| docker exec -it clab-<lab>-<node> Cli | Connect to an Arista cEOS node's CLI directly through Docker |
| docker exec -it clab-<lab>-<node> sr_cli | Connect to a Nokia SR Linux node's CLI directly through Docker |
| ssh admin@<node-name> | Connect to a node over SSH using the hostname Containerlab registered in /etc/hosts |

## Arista EOS

| Command | Usage |
|---|---|
| enable | Enter privileged exec mode after logging in over SSH |
| show version | Display the running EOS software version |
| show interfaces status | Display interface link status |
| show ip interface brief | Display interface IP addresses and status |
| configure / end | Enter and leave global configuration mode |
| interface <name> | Enter interface configuration mode |
| no switchport | Convert a physical interface from switchport to routed mode |
| ip address <address>/<prefix> | Assign an IPv4 address to a routed interface |
| no shutdown | Administratively enable an interface |
| ping <address> | Test reachability to an address |

## Nokia SR Linux

| Command | Usage |
|---|---|
| show version | Display the running SR Linux software version |
| show interface brief | Display a summary of all interfaces |
| show interface <name> | Display detailed status for one interface |
| enter candidate | Enter the candidate configuration datastore |
| set / interface <name> subinterface <index> ipv4 admin-state enable | Enable IPv4 on a subinterface |
| set / interface <name> subinterface <index> ipv4 address <address>/<prefix> | Assign an IPv4 address to a subinterface |
| set / network-instance default interface <name>.<index> | Associate a subinterface with the default network instance so it forwards traffic |
| diff | Show the difference between the candidate and running configuration before committing |
| commit now | Commit the candidate configuration and return to running mode |
| discard stay | Discard candidate changes and remain in candidate mode |
| quit | Leave the SR Linux CLI session |
| ping <address> network-instance default | Test reachability to an address within a given network instance |

## Default Credentials

| Kind | Username | Password |
|---|---|---|
| Arista cEOS | admin | admin |
| Nokia SR Linux | admin | NokiaSrl1! |

## Python and Netmiko

| Command | Usage |
|---|---|
| python3 -m venv .velab2 | Create a virtual environment |
| source .velab2/bin/activate | Activate a virtual environment |
| pip install <package> | Install a package inside the active environment |
| pip freeze > requirements.txt | Record installed packages and their versions |
| ConnectHandler(**params) | Open a Netmiko connection to a device |
| connection.send_command(<command>) | Send a command and return its output as a string |
| re.finditer(pattern, text) | Iterate over every regex match in a string |
| match.group("<name>") | Retrieve a named capture group from a regex match |
