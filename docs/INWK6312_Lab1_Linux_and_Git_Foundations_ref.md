---
title: Lab 1
subtitle: Linux Foundations and Version Control for Network Engineers
highlight-style: tango
toc: true
output:
    pdf_document:
        toc_depth: 2
        highlight: custom-tango.theme # option: tango, pygments, kate, monochrome, espresso, haddock, breezedark
geometry: margin=1in
header-includes:
  - \usepackage{fvextra}
  - \DefineVerbatimEnvironment{Highlighting}{Verbatim}{breaklines,commandchars=\\\{\}}
---

\newpage

# Introduction

This lab covers material from both Lecture 1 and Lecture 2. You will spend the first part of the lab working directly on your assigned Ubuntu virtual machine, building a small routed network entirely out of Linux network namespaces. You will then version that work using Git and publish it to a personal repository created through GitHub Classroom. That repository is not a one time deliverable, it becomes the working repository you will keep extending in Labs 2 through 5, so treat your commit history and folder structure as something future you will rely on.

# Lab Objectives

By the end of this lab, you will be able to:

1. Navigate the Linux filesystem and manage file ownership and permissions from the shell
2. Parse and manipulate text using cat, grep, cut, and sed
3. Control a systemd service through its full lifecycle, start, status, enable, stop, and read its logs with journalctl
4. Inspect and configure Linux network interfaces, addresses, and routes using iproute2
5. Build an isolated, routed network topology using network namespaces and veth pairs
6. Automate the creation and teardown of that topology with a bash script
7. Track infrastructure files through Git's working directory, staging area, and local repository
8. Create and merge branches, and resolve a merge conflict by hand
9. Publish a repository to GitHub Classroom and complete a pull request based review cycle

# Lab Environment and Preparation

You will need:

- Your assigned Ubuntu VM, reachable over SSH, with sudo privileges on your own account
- git, openssh, iproute2, vim, and nano preinstalled on the VM
- A GitHub account
- The GitHub Classroom assignment link, distributed separately by the instructor, which will generate your personal repository for this course

If any of the tools above are missing when you get to that step, check with your lab instructor before trying to install anything yourself, since the VM image is meant to already have everything you need.

Throughout this document, commands you type are shown in code blocks. Where a command needs elevated privileges it is shown with sudo. If a step does not show sudo, you should not need it.

\newpage

# Part A: Linux Foundations

## Task 0: Connecting to Your Lab VM

Objective: get comfortable with your terminal emulator and get your bearings in nano and vim, since these will be the editors used for most of the course.

1. Confirm you have a working terminal emulator on your own laptop. Windows Command Pormpt, PuTTY, or MobaXTerm on Windows, or the built in Terminal app on macOS and Linux, are all fine.

2. Start the terminal (next we assume Windows CMD), and use SSH to login in to the assigned VM:

    ```bash
    ssh student@<VM IP Address>
    ```

3. Enter the password `Meilab123`

4. Practice with nano. Create a file, add a line of text, then save and exit using `Ctrl+O, Enter, Ctrl+X`. You can also `Ctrl-X` directly then `Y, Enter` at the prompt.

    ```bash
    nano welcome.txt
    ```

5. Practice with vim on the same file. Press `i` to enter Insert mode, make a change by adding few lines of text, press `Esc` to return to Normal mode.

    ```bash
    vim welcome.txt
    ```

6. Still in vim, practice moving around with `h, j, k, and l` instead of the arrow keys, and try `dd` to delete a line and `u` to undo. Save and quit with `:wq, Enter`

### Questions and Deliverables

1. What is the difference between Normal mode and Insert mode in vim, and which key takes you from Normal mode into Insert mode?
2. Run `cat welcome.txt` after step 6 and provide the output.

## Task 1: Filesystem Navigation and Permissions

Objective: navigate the filesystem confidently and understand how Linux permissions and ownership work, since every file you manage in this course, from topology definitions to playbooks, lives inside this permission model.

1. Confirm your current location and move around.

    ```bash
    pwd
    ls -l
    cd ~
    ```

2. Create your working directory for this lab and this course.

    ```bash
    mkdir -p ~/labs/lab1/configs
    mkdir -p ~/labs/lab1/scripts
    cd ~/labs/lab1
    ```

3. Create a sample file and inspect its permission bits.

    ```bash
    touch configs/sample.txt
    ls -l configs/sample.txt
    ```

Identify the owner, the group, and the three permission triplets, owner, group, and other.

4. Change the permission bits so only you can read and write the file, and no one else has any access.

    ```bash
    chmod 600 configs/sample.txt
    ls -l configs/sample.txt
    ```

5. Practice changing file permissions by restricting group access to read-only.

    ```bash
    chmod 644 configs/sample.txt
    ```

### Questions and Deliverables 

1. What is the purpose of the `~` in the steps 1 and 2 above?
2. What does the option `-p` do in step 2?
3. Show file permissions after step 5. 

## Task 2: Text Processing Toolkit

Objective: use small, precise Linux tools together to pull information out of a configuration style text file, the same way you would pull data out of a real device's running config.

1. While in `~/labs/lab1' directory, create a sample configuration file to work with (do not cut-paste the last EOF).

    ```bash
    cat > configs/sample-config.txt << 'EOF'
    hostname R1
    interface GigabitEthernet0/0
    description Uplink to Core
    ip address 10.1.1.1 255.255.255.0
    interface GigabitEthernet0/1
    description Access VLAN10
    ip address 10.1.10.1 255.255.255.0
    interface GigabitEthernet0/2
    description Access VLAN20
    ip address 10.1.20.1 255.255.255.0
    router ospf 1
    network 10.1.1.0 0.0.0.255 area 0
    network 10.1.10.0 0.0.0.255 area 0
    EOF
    ```

2. View the whole file.

    ```bash
    cat configs/sample-config.txt
    ```

3. Use grep to find every interface line.

    ```bash
    grep "interface" configs/sample-config.txt
    ```

4. Use grep to find every IP address line, then pipe the result into cut to extract just the address.

    ```bash
    grep "ip address" configs/sample-config.txt
    grep "ip address" configs/sample-config.txt | cut -d ' ' -f 3
    ```

5. Count how many interfaces are configured, by piping grep into wc.

    ```bash
    grep -c "interface" configs/sample-config.txt
    ```

6. Use sed to preview a change without touching the file. Change VLAN10 to VLAN30 in the output only.

    ```bash
    sed 's/VLAN10/VLAN30/' configs/sample-config.txt
    ```

7. Confirm the file itself was not modified, then make the change permanent with -i.

    ```bash
    cat configs/sample-config.txt
    sed -i 's/VLAN10/VLAN30/' configs/sample-config.txt
    cat configs/sample-config.txt
    ```

8. Use sed to print only the first five lines, as an alternative to head.

    ```bash
    sed -n '1,5p' configs/sample-config.txt
    ```

### Questions and Deliverables 

1. Provide the modified file `sample-config.txt`
2. Describe, briefly, the general application of each tools used in this task.

## Task 3: systemd Service Management

Objective: control a service through its full lifecycle without touching the SSH service you are currently connected through.

1. Create a small systemd unit file. This needs sudo since unit files live under /etc.

    ```bash
    sudo nano /etc/systemd/system/inwk-demo.service
    ```

    Enter the following content, save, and exit.

    ```ini
    [Unit]
    Description=INWK6312 Demo Service

    [Service]
    ExecStart=/usr/bin/sleep infinity
    Restart=always

    [Install]
    WantedBy=multi-user.target
    ```

2. Reload systemd so it picks up the new unit file.

    ```bash
    sudo systemctl daemon-reload
    ```

3. Start the service and check its status (save the output).

    ```bash
    sudo systemctl start inwk-demo
    systemctl status inwk-demo
    ```

4. Enable the service so it would start automatically on boot.

    ```bash
    sudo systemctl enable inwk-demo
    ```

5. Stop the service and check status again, notice the difference between a stopped service and a failed one.

    ```bash
    sudo systemctl stop inwk-demo
    systemctl status inwk-demo
    ```

6. Read the service's logs using journalctl.

    ```bash
    journalctl -u inwk-demo
    ```

7. Start the service one more time and leave it running for the rest of the lab, you will not need it again but it is a harmless background process.

    ```bash
    sudo systemctl start inwk-demo
    ```

### Questions and Deliverables 

1. Provide the output of steps 3, 5, and 6 above.


## Task 4: IP Address and Link Management with iproute2

Objective: use the ip command to inspect and lightly modify the VM's own network configuration.

1. List the VM's interfaces and note which ones are UP.

    ```bash
    ip link show
    ```

2. List the addresses assigned to each interface.

    ```bash
    ip addr show
    ```

3. View the routing table and identify the default route.

    ```bash
    ip route show
    ```

4. View the neighbor table, the Linux equivalent of an ARP table.

    ```bash
    ip neighbor show
    ```

5. Add a harmless secondary address to the loopback interface, confirm it, then remove it.

    ```bash
    sudo ip addr add 192.0.2.1/24 dev lo
    ip addr show lo
    sudo ip addr del 192.0.2.1/24 dev lo
    ip addr show lo
    ```

6. View active listening sockets on the VM.

    ```bash
    ss -tulpn
    ```

7. Test reachability to a known external host and read the output. Recent Ubuntu distributions longer ship `traceroute` by default, `mtr` is the alternative tools and it combines `ping` and `traceroute` style output in one tool.

    ```bash
    ping -c 3 8.8.8.8
    mtr -c 3 8.8.8.8
    ```

### Questions and Deliverables

1. What is the purpose of the option `-c 3` in step 7? What will happen if it is removed?
2. Provide the output of the mtr command from step 7.


## Task 5: Network Namespaces and Virtual Wires

Objective: build two fully isolated network stacks on the same VM and connect them with a virtual patch cable, a veth pair.

Before you start, understand what you are building. ns-red and ns-blue are two independent network stacks, each with its own interfaces, addresses, and routing table, completely invisible to each other and to the VM's own network stack until you connect them. A veth pair is a virtual patch cable, created as a single object with two ends, where each end can be moved into a different namespace. Work through the steps in order and check the output after each one, since a namespace or interface that did not get created or moved correctly is the most common reason the connectivity test at the end fails silently.

1. Create two namespaces and confirm they exist.

    ```bash
    sudo ip netns add ns-red
    sudo ip netns add ns-blue
    ip netns list
    ```

2. Create a veth pair, one end named for each namespace.

    ```bash
    sudo ip link add veth-red type veth peer name veth-blue
    ```

3. Move each end into its namespace.

    ```bash
    sudo ip link set veth-red netns ns-red
    sudo ip link set veth-blue netns ns-blue
    ```

    Verify the move worked before continuing. The host's own namespace should no longer list these two interfaces, since they now belong to ns-red and ns-blue.

    ```bash
    ip link show
    sudo ip netns exec ns-red ip link show
    sudo ip netns exec ns-blue ip link show
    ```

4. Assign an IP address to each end.

    ```bash
    sudo ip netns exec ns-red ip addr add 10.10.10.1/24 dev veth-red
    sudo ip netns exec ns-blue ip addr add 10.10.10.2/24 dev veth-blue
    ```

5. Bring each interface up, and bring up the loopback inside each namespace too, since a new namespace starts with everything down.

    ```bash
    sudo ip netns exec ns-red ip link set veth-red up
    sudo ip netns exec ns-red ip link set lo up
    sudo ip netns exec ns-blue ip link set veth-blue up
    sudo ip netns exec ns-blue ip link set lo up
    ```

    Verify both interfaces are up and carry the address you assigned, before testing connectivity.

    ```bash
    sudo ip netns exec ns-red ip addr show veth-red
    sudo ip netns exec ns-blue ip addr show veth-blue
    ```

    Confirm each output shows state UP and the address you assigned in step 4. If either shows DOWN or has no address, go back before continuing.

6. Test connectivity from ns-red to ns-blue.

    ```bash
    sudo ip netns exec ns-red ping -c 3 10.10.10.2
    ```

7. Inspect the neighbor table inside ns-red, it should now have learned ns-blue's MAC address.

    ```bash
    sudo ip netns exec ns-red ip neighbor show
    ```

You now have two isolated hosts talking to each other over a virtual wire. Keep this in mind, future labs will do the same thing for you at a larger scale, using the same underlying kernel features.

### Questions and Deliverables

1. Provide the output of the verification commands from step 3. Which namespace's output no longer lists veth-red and veth-blue on the host itself, and why not.
2. Provide the output of the ping test in step 6 and the neighbor table output from step 7.

## Task 6: Building a Mini Routed Topology with Namespaces

Objective: extend Task 5 into a three namespace topology, two hosts and a router, so you can see why a Linux router forwards traffic that two directly connected namespaces cannot reach on their own.


Target topology:

```plaintext
ns-hostA (10.10.1.2/24) -- ns-router (10.10.1.1/24, 10.10.2.1/24) -- ns-hostB (10.10.2.2/24)
```

1. Clean up the namespaces from Task 5, then create three fresh ones.

    ```bash
    sudo ip netns del ns-red
    sudo ip netns del ns-blue
    sudo ip netns add ns-hostA
    sudo ip netns add ns-router
    sudo ip netns add ns-hostB
    ```

2. Create the first veth pair, between ns-hostA and ns-router.

    ```bash
    sudo ip link add veth-a type veth peer name veth-r1
    sudo ip link set veth-a netns ns-hostA
    sudo ip link set veth-r1 netns ns-router
    ```

3. Create the second veth pair, between ns-router and ns-hostB.

    ```bash
    sudo ip link add veth-r2 type veth peer name veth-b
    sudo ip link set veth-r2 netns ns-router
    sudo ip link set veth-b netns ns-hostB
    ```

    Verify every interface landed in the right namespace before continuing.

    ```bash
    for ns in ns-hostA ns-router ns-hostB; do
      echo "-- $ns --"
      sudo ip netns exec $ns ip link show
    done
    ```

    ns-hostA should show veth-a, ns-router should show both veth-r1 and veth-r2, and ns-hostB should show veth-b.

4. Assign addresses on each leg.

    ```bash
    sudo ip netns exec ns-hostA ip addr add 10.10.1.2/24 dev veth-a
    sudo ip netns exec ns-router ip addr add 10.10.1.1/24 dev veth-r1
    sudo ip netns exec ns-router ip addr add 10.10.2.1/24 dev veth-r2
    sudo ip netns exec ns-hostB ip addr add 10.10.2.2/24 dev veth-b
    ```

5. Bring every interface and every loopback up.

    ```bash
    for ns in ns-hostA ns-router ns-hostB; do
    sudo ip netns exec $ns ip link set lo up
    done
    sudo ip netns exec ns-hostA ip link set veth-a up
    sudo ip netns exec ns-router ip link set veth-r1 up
    sudo ip netns exec ns-router ip link set veth-r2 up
    sudo ip netns exec ns-hostB ip link set veth-b up
    ```

    Verify every interface is up and carries the address you expect, before moving on to routing.

    ```bash
    for ns in ns-hostA ns-router ns-hostB; do
      echo "-- $ns --"
      sudo ip netns exec $ns ip addr show
    done
    ```

6. Enable IP forwarding inside ns-router only, this is the single kernel bit that turns it from a host into a router.

    ```bash
    sudo ip netns exec ns-router sysctl -w net.ipv4.ip_forward=1
    ```

    Confirm forwarding is actually enabled before testing connectivity, this is a common step to forget.

    ```bash
    sudo ip netns exec ns-router sysctl net.ipv4.ip_forward
    ```

    The output should read `net.ipv4.ip_forward = 1`.

7. Add static routes on each host so they know how to reach the far subnet.

    ```bash
    sudo ip netns exec ns-hostA ip route add 10.10.2.0/24 via 10.10.1.1
    sudo ip netns exec ns-hostB ip route add 10.10.1.0/24 via 10.10.2.1
    ```

8. Test end to end connectivity from ns-hostA to ns-hostB.

    ```bash
    sudo ip netns exec ns-hostA ping -c 3 10.10.2.2
    ```

9. Before you added the static route, this ping would have failed even though both hosts have a valid interface, since Linux drops packets to unknown destinations instead of broadcasting for them the way Layer 2 does. Confirm this by checking ns-hostA's route table, and identify which line makes 10.10.2.2 reachable.

    ```bash
    sudo ip netns exec ns-hostA ip route show
    ```

10. Optionally, watch the traffic transit ns-router in real time in a second terminal while you repeat the ping.

    ```bash
    sudo ip netns exec ns-router tcpdump -i veth-r1 icmp
    ```

### Questions and Deliverables

1. Provide the output of the forwarding verification command from step 6, and the output of the ping test in step 8.
2. In your own words, explain what would have happened in step 8 if IP forwarding had not been enabled on ns-router, even though the static routes on ns-hostA and ns-hostB were both correctly configured.

## Task 7: Automating It With Bash

Objective: turn Task 6 into a repeatable script, since manually retyping fifteen commands every time you need this topology is exactly the kind of manual operational pitfall Lecture 1 opened with.

1. Create a script file.

    ```bash
    nano ~/labs/lab1/scripts/build-topology.sh
    ```

2. Start from this skeleton, then extend it yourself to complete the full topology from Task 6, including the veth pairs, IP addresses, interfaces up, IP forwarding, and static routes.

    ```bash
    #!/bin/bash
    # build-topology.sh
    # Builds the INWK6312 Lab 1 routed namespace topology: 
    # ns-hostA -- ns-router -- ns-hostB

    set -e

    NAMESPACES=("ns-hostA" "ns-router" "ns-hostB")

    for ns in "${NAMESPACES[@]}"; do
    if ip netns list | grep -q "^$ns"; then
        echo "$ns already exists, skipping"
    else
        ip netns add "$ns"
        echo "Created $ns"
    fi
    done

    # TODO: create the veth pairs and move each end into the right namespace
    # TODO: assign addresses to each interface
    # TODO: bring up every interface and every loopback
    # TODO: enable IP forwarding on ns-router
    # TODO: add the static routes on ns-hostA and ns-hostB

    echo "Topology build complete"
    ```

3. Make the script executable and run it as root, since ip netns operations require it.

    ```bash
    chmod +x ~/labs/lab1/scripts/build-topology.sh
    sudo ~/labs/lab1/scripts/build-topology.sh
    ```

    Verify the script actually built a working topology, not just three empty namespaces, by repeating the connectivity test from Task 6, step 8.

    ```bash
    sudo ip netns exec ns-hostA ping -c 3 10.10.2.2
    ```

    If this fails, revisit the TODO sections in your script before continuing, do not move on with a broken build.

4. Run the script a second time without cleaning up first, and confirm the existence check in the loop stops it from failing on namespaces that are already there. This is the same idempotency idea that Ansible relies on, which you will see again in Lecture 8.

5. Write a companion teardown script that deletes the three namespaces, again using a loop, and again checking whether each namespace exists before trying to delete it.

    ```bash
    nano ~/labs/lab1/scripts/teardown-topology.sh
    ```

    ```bash
    #!/bin/bash
    # teardown-topology.sh

    NAMESPACES=("ns-hostA" "ns-router" "ns-hostB")

    for ns in "${NAMESPACES[@]}"; do
    if ip netns list | grep -q "^$ns"; then
        ip netns del "$ns"
        echo "Deleted $ns"
    else
        echo "$ns does not exist, skipping"
    fi
    done
    ```

    ```bash
    chmod +x ~/labs/lab1/scripts/teardown-topology.sh
    sudo ~/labs/lab1/scripts/teardown-topology.sh
    ```

    Verify the namespaces are actually gone.

    ```bash
    ip netns list
    ```

    None of ns-hostA, ns-router, or ns-hostB should appear.

6. Run `build-topology.sh` one more time and confirm the topology comes back up cleanly, then re-run the connectivity test from Task 6, step 8, to verify.

You now have working, reusable code for something you previously did by hand. That is the entire point of this lab, and of the course.

### Questions and Deliverables

1. Provide the completed scripts generated on previous steps.
2. Provide the output confirming the teardown script removed all three namespaces in step 5, and the output confirming the topology was rebuilt and reachable again in step 6.


\newpage

# Part B: Git and GitHub

## Task 8: Initializing Your Course Repository

Objective: bring your Part A work under version control, so every change from here on is tracked, attributable, and reversible.

1. Move into your `~/labs` directory, which will become the root of your Git repository.

    ```bash
    cd ~/labs
    git init
    ```

2. Set your identity, this is what will appear on every commit you make.

    ```bash
    git config --global user.name "Your Name"
    git config --global user.email "your_email@dal.ca"
    ```

3. Create a .gitignore file to keep editor and OS junk out of your history.

    ```bash
    cat > .gitignore << 'EOF'
    *.swp
    *.swo
    .DS_Store
    *.key
    EOF
    ```

4. Display the current state of your Git working directory and staging area.

    ```bash
    git status
    ```

    Take note of the untracked files and directories.

5. Stage your Part A work.

    ```bash
    git add scripts/build-topology.sh scripts/teardown-topology.sh .gitignore
    git status
    ```
    Take notes of the new files.

6. Commit changes and confirm the commit exists.

    ```bash
    git commit -m "Initial commit: namespace topology automation scripts"
    git log
    ```
### Questions and Deliverables

1. Compare the git status output from step 4, before staging, with the output from step 5, after staging. What changed, and which files moved from untracked to staged?
2. Provide the output of git log from step 6.


## Task 9: Staging, Committing, and Reviewing History

Objective: practice the modify, stage, commit cycle deliberately, get comfortable reading diffs and history, and learn how to safely back out of a change you decide you don't want, whether it is still in your working directory or already staged.

1. Add a short comment header to the top of `build-topology.sh` describing what the script does and who wrote it.

2. See the unstaged change.

    ```bash
    git diff
    ```

3. Stage it and see the staged version of the diff.

    ```bash
    git add scripts/build-topology.sh
    git diff --staged
    ```

4. Commit the change with a message that explains why, not just what.

    ```bash
    git commit -m "Document script purpose in a header comment"
    ```

5. Now practice discarding a change you decide not to keep. Add a throwaway line near the top of `build-topology.sh`, something like `# TEMP: testing restore`, that you have no intention of committing.

6. Confirm Git sees it as an unstaged modification.

    ```bash
    git status
    git diff
    ```

7. Discard the change entirely, returning the file to its last committed state.

    ```bash
    git restore scripts/build-topology.sh
    git status
    git diff
    ```

    Both `git status` and `git diff` should now show a clean working directory, the throwaway line is gone, not just hidden.

8. Practice the second case: unstaging a change without losing it. Add another throwaway line to `build-topology.sh`, then stage it as if you had meant to commit it.

    ```bash
    git add scripts/build-topology.sh
    git status
    ```

9. Realize you staged the wrong thing, and move it back to the working directory without discarding the edit itself.

    ```bash
    git restore --staged scripts/build-topology.sh
    git status
    ```

    Notice the file is now back to modified but unstaged, not staged and not gone. This is the difference between the two commands, one discards, the other only unstages.

10. Since this second line was also throwaway, clean it up before continuing, so your working directory is not left dirty going into the next task.

    ```bash
    git restore scripts/build-topology.sh
    git status
    ```

11. Add your Task 2 `sample-config.txt` to version control as well.

    ```bash
    git add configs/sample-config.txt
    git commit -m "Add sample device config used for text processing practice"
    ```

12. Review your history so far in condensed form.

    ```bash
    git log --oneline
    ```

### Questions and Deliverables

1. Provide the output of `git diff --staged` from step 3, and briefly explain how it differs from the plain `git diff` you ran in step 2.
2. Compare `git restore <file>` from step 7 with `git restore --staged <file>` from step 9. What is the effect of each on the working directory versus the staging area, and if you had staged the wrong file by mistake but wanted to keep the edit, which of the two would you use?
3. Provide the output of `git log --oneline` from step 12.


## Task 10: Branching for Safe Changes

Objective: make a change on an isolated branch instead of directly on master, and confirm that isolation actually holds.

1. Create and switch to a feature branch in one step then confirm the new branch is active.

    ```bash
    git switch -c feature/add-hostC
    git branch
    ```

2. Edit `build-topology.sh` and `teardown-topology.sh` to add a third host, `ns-hostC`, connected to `ns-router` on a new subnet, `10.10.3.0/24`. Extend the `NAMESPACES` array, add the new veth pair, address, route, and forwarding logic, following the same pattern as `ns-hostA` and `ns-hostB`.

3. Test your updated script.

    ```bash
    sudo ~/labs/lab1/scripts/teardown-topology.sh
    sudo ~/labs/lab1/scripts/build-topology.sh
    sudo ip netns exec ns-hostC ping -c 3 10.10.1.2
    ```

4. Stage and commit the change on the feature branch.

    ```bash
    git add scripts/build-topology.sh scripts/teardown-topology.sh
    git commit -m "Add ns-hostC as a third host on the topology"
    ```

5. Switch back to master and confirm the change is not there, this is branch isolation in action.

    ```bash
    git switch master
    cat scripts/build-topology.sh
    ```

6. Merge the feature branch into master. Since master has not changed since you branched, this should be a fast forward merge.

    ```bash
    git merge feature/add-hostC
    ```

7. Confirm master now includes `ns-hostC`.

### Questions and Deliverables

1. Provide the output of git branch from step 1, confirming which branch was active.
2. In step 5, `cat scripts/build-topology.sh` on master should not show `ns-hostC` yet. Provide that output, and explain in one sentence why the change is not visible there.

## Task 11: Simulating and Resolving a Merge Conflict

Objective: Simulate a conflict using two branches that each change the same line differently, then resolve the conflict by hand.

1. From master, create the first experimental branch.

    ```bash
    git switch -c experiment/subnet-a
    ```

2. In `build-topology.sh`, change the subnet used for `ns-hostA` from `10.10.1.0/24` to `10.10.11.0/24`, updating every line that references it. Commit.

    ```bash
    git add scripts/build-topology.sh
    git commit -m "Renumber ns-hostA subnet to 10.10.11.0/24"
    ```

3. Go back to master and create a second experimental branch from there.

    ```bash
    git switch master
    git switch -c experiment/subnet-b
    ```

4. In `build-topology.sh`, change the same lines, but to a different subnet, `10.10.21.0/24` instead. Commit.

    ```bash
    git add scripts/build-topology.sh
    git commit -m "Renumber ns-hostA subnet to 10.10.21.0/24"
    ```

5. Go back to master and merge the first branch. Since master has not changed, this merge should be clean.

    ```bash
    git switch master
    git merge experiment/subnet-a
    ```

6. Now merge the second branch, this time Git cannot decide which subnet is correct, since both branches changed the same lines starting from the same point.

    ```bash
    git merge experiment/subnet-b
    ```

7. Open `build-topology.sh` and look for the conflict markers, `<<<<<<<, =======, and >>>>>>>`. Decide which subnet you want to keep, in this case `10.10.21.0/24` is a reasonable choice since it was merged second, then edit the file so it contains only the correct lines and none of the conflict markers.

8. Stage the resolved file and complete the merge commit. Git will pre-fill a merge commit message, you can accept it or adjust it.

    ```bash
    git add scripts/build-topology.sh
    git commit
    ```

9. Confirm the topology still works after resolving the conflict.

    ```bash
    sudo ~/labs/lab1/scripts/teardown-topology.sh
    sudo ~/labs/lab1/scripts/build-topology.sh
    ```

10. Visualize the branch and merge history.

    ```bash
    git log --graph --oneline --all
    ```

11. Create a short file named REFLECTION.md and write two or three sentences comparing how this same conflict would have been handled differently under a strict Gitflow model, with a shared develop branch and a formal release branch, versus the simple feature branching you used here. Add and commit it.

    ```bash
    git add REFLECTION.md
    git commit -m "Add reflection on Gitflow versus feature branching"
    ```

## Task 12: Publishing to GitHub and Opening a Pull Request

Objective: connect your local repository to GitHub Classroom, publish your history, and complete one pull request based review cycle.

Every task before this one used a local merge, since you were merging your own branches into your own repository with no one else involved. Publishing changes this. A pull request is the checkpoint where a change is proposed and reviewed before it lands on master, the branch other people rely on. Real teams do not push directly to a shared master branch, peer review catches mistakes early, and the pull request becomes a permanent, visible record of what changed and why. In this lab are working alone, so you will play both roles, but the steps are identical to a real team workflow.

1. Open the GitHub Classroom assignment link provided by the instructor and accept it. This creates a personal repository under the course organization and gives you its clone URL.

2. Connect your local repository to that remote. GitHub no longer accepts your account password for Git operations over HTTPS, you need a personal access token instead. On GitHub, go to Settings, Developer settings, Personal access tokens, generate one with at least repo scope, and copy it somewhere safe, you will not be able to view it again. When the push below prompts you for a password, paste the token instead.

    ```bash
    git remote add origin <your-classroom-repo-url>
    git push -u origin master
    ```

3. Confirm on the GitHub website that master is visible, along with your commit history.

4. Create one more small branch for a README.

    ```bash
    git switch -c docs/readme
    ```

5. Create a `README.md` describing the topology, what each script does, and how to run them.

    ```bash
    nano README.md
    ```

6. Stage, commit, and push the branch.

    ```bash
    git add README.md
    git commit -m "Add README describing the lab topology and scripts"
    git push -u origin docs/readme
    ```

7. On the GitHub website, open a pull request from docs/readme into master.

8. Since you are working solo this week, review your own pull request, add at least one inline comment on the diff pointing out something a reviewer would actually want to know, then merge the pull request using the GitHub web interface.

9. Bring the merged change back down to your local master branch.

    ```bash
    git switch master
    git pull
    ```

### Questions and Deliverables

1. Provide the URL of your merged pull request.
2. Why does GitHub require a personal access token instead of your account password for pushing over HTTPS?

# Clean Up

Leave the inwk-demo systemd service running, it is harmless. Leave your namespace topology up or torn down, either is fine, since it is fully defined in your scripts and can be rebuilt at any time.

Do not delete your GitHub Classroom repository. You will keep building on it in Lab 2, where the Containerlab topology definition you create will live alongside the scripts and configs you built today.

# Submission

Confirm your repository history includes, at minimum, the following, then submit your repository link as instructed by your course delivery platform:

- The initial commit of `build-topology.sh` and `teardown-topology.sh`
- The documentation and sample config commits from Task 9
- The `ns-hostC` feature merge from Task 10
- The resolved merge conflict from Task 11, visible as a merge commit in `git log --graph`
- `REFLECTION.md`
- The docs/readme pull request, merged, visible on GitHub Classroom

    ```bash
    git log --oneline --graph --all
    ```

\newpage

# Appendix: Command Summary

## Linux and iproute2

| Command | Usage |
|---|---|
| pwd, ls -l, cd | Navigate and inspect the filesystem |
| chmod, chown | Change permissions and ownership |
| cat, grep, cut, sed | View and process text |
| systemctl start/stop/status/enable | Control a systemd service |
| journalctl -u <service> | Read logs for a specific service |
| ip link show / set | View and change interface state |
| ip addr show / add / del | View and change IP addresses |
| ip route show / add | View and change the routing table |
| ip neighbor show | View the ARP/neighbor cache |
| ip netns add / del / list / exec | Create, remove, list, and run commands inside namespaces |
| ip link add type veth peer name | Create a veth pair |
| sysctl -w net.ipv4.ip_forward=1 | Enable IP forwarding in the current namespace |

## Git

| Command | Usage |
|---|---|
| git init | Create a new local repository |
| git config --global user.name / user.email | Set commit identity |
| git status | Show staged and unstaged changes |
| git diff / git diff --staged | Show unstaged or staged changes |
| git add | Move a change into the staging area |
| git commit -m | Record a staged snapshot |
| git log / git log --oneline / git log --graph --all | View commit history |
| git switch -c | Create and switch branches |
| git branch | List brances | 
| git restore | Discard file edits and returning to its last committed state
| git merge | Combine one branch's history into another |
| git remote add origin | Link a local repository to a remote |
| git push -u origin <branch> | Publish a branch to the remote |
| git pull | Fetch and merge remote changes into the current branch |
