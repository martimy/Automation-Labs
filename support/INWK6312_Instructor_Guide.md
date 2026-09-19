---
title: INWK6312 Instructor Lab Guide, 
subtitle: Troubleshooting, Tools, and Recovery Procedures
highlight-style: tango
fontsize: 11pt
numbersections: false
colorlinks: true
listings: true
documentclass: article
output:
    pdf_document:
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


Audience: anyone helping run an INWK6312 lab session, including instructors and TAs who are not deeply familiar with containerlab, NETCONF, gNMI, Ansible, NetBox, or Batfish. The goal of this guide is that a TA who knows Linux and Git, but not these specific tools, can still triage most problems using this document alone, and knows exactly when a problem is beyond that and needs to be escalated.

This is a living document. When a new problem type shows up during a session, add it here afterward, even in rough form. A half-written entry someone adds the same day is worth more than a polished one written from memory a month later.

# How This Guide Is Organized

1. What is actually running, a short map of the environment, useful context before diagnosing anything.
2. Triage first steps, the same handful of checks to run before anything more specific.
3. Problems by category, matched to the student guide's categories so the two documents stay easy to cross-reference.
4. When to escalate to a VM snapshot restore, and what to collect before you do.
5. Known trouble spots by lab.
6. Maintaining this guide.

# What Is Actually Running

Each student has their own Ubuntu VM. Everything in these labs runs inside that VM, there is no shared infrastructure between students except GitHub Classroom itself. This means a student's mistake, short of literally corrupting their own VM, cannot affect anyone else.

Inside the VM, the pieces in play across the five labs are:

- Containerlab, running a persistent topology named `lab-net`, three or five nodes depending on the lab, saved to and restored from a `clab-lab-net` folder under `~/labs/topology`. This folder is the single most important piece of persistent state in the course, if a student loses it, they lose their configured network and have to rebuild it from the Appendix configuration tables in each lab.
- A Python virtual environment, `~/labs/.velab`, holding the packages the labs need, `ncclient`, `pygnmi`, `netmiko`, `ansible`, `pynetbox`, `pybatfish`, and so on.
- A git repository at `~/labs`, pushed to a GitHub Classroom repository, this is what students submit.
- A separate tools clone at `~/tools` or `~/labs/tools` (student scripts, `nc_wrapper.sh`, `netconf_tool.py`, `gnmi_tool.py`, `devicelib.py`), kept outside the student's own repository on purpose, so a student cloning your tools does not end up with a nested git repository inside their own.
- Starting in Lab 5, a NetBox instance running under Docker Compose in `~/netbox-docker`, and a Batfish container started and stopped by name (`batfish`).
- Starting in Lab 5, a GitHub Actions workflow in the student's own repository, which runs a Batfish check remotely on push, this is the one piece of the course that runs somewhere other than the student's VM.

If you only remember one thing from this section: almost every "the network is broken" problem is fixed by redeploying `lab-net` from its saved state, and almost every "my repository is a mess" problem is fixed by resetting to the most recent `labN-complete` git tag. Knowing this covers a large fraction of what comes up.

# Triage First Steps

Before diagnosing anything specific, run these. They take under a minute and rule out the most common root causes.

```bash
pwd
ls ~/labs
git -C ~/labs status
git -C ~/labs log --oneline -5
sudo containerlab inspect -t ~/labs/topology/lab-net.clab.yml
```

What you are looking for:

- `pwd` and `ls ~/labs`, confirms the student is where they think they are, and that the expected folder structure exists.
- `git status`, an unexpectedly large number of modified or untracked files is often the actual problem, even if the student described something else.
- `git log --oneline -5`, confirms whether the student has commits and tags from previous labs, if `labN-complete` tags are missing entirely, `git reset --hard` is not available as a recovery option and you are working with a smaller toolkit.
- `containerlab inspect`, confirms the topology is actually up. If it reports nothing running, the "broken network" the student is describing may simply be an undeployed topology, not a configuration problem at all.

If those all look normal, move to the category-specific sections below.

# Problems by Category

## Path and location mistakes

Symptom: a command failed with "no such file or directory," or a file the student expects to exist is missing, or is in the wrong place.

Check: `pwd`, then `find ~ -maxdepth 5 -iname "<filename>"` to locate where the file actually ended up. A missing `~` or forgetting to `cd` first before a relative path is the most common cause across all five labs.

Fix: move or recreate the file in the correct location, there is essentially never a need to do anything more drastic than this for a misplaced file.

## Destroyed or lost topology state

Symptom: containerlab redeploys, but the resulting nodes have no configuration, blank interfaces, no addresses, nothing beyond the base image default.

Check: `ls ~/labs/topology/clab-lab-net` (or the Lab 2 through Lab 4 path if the student is still on those labs). If this folder is missing or empty, the saved state is gone.

Likely cause: `containerlab destroy` was run with `--cleanup` against `lab-net` at some point instead of one of the disposable single-node test topologies in early Lab 2. This flag deletes the saved configuration folder as well as the containers.

Fix: there is no way to recover the specific saved state once `--cleanup` has deleted it. The fastest path forward is to walk the student through reapplying the Appendix configuration tables from whichever labs they have completed, in order, this is mechanical and usually faster than it sounds, since the Appendix tables in each lab already contain the exact commands needed. If the student is more than two labs deep, this is a good moment to also remind them to actually use the `git tag labN-complete` checkpoints going forward, since that habit does not protect topology state but does protect their repository from the same category of loss.

## Git repository is a mess

Symptom: student describes conflicting or confusing output from `git status`, cannot commit, or is unsure what state their repository is in.

Check: `git log --oneline --all --graph` gives a fast visual sense of what has happened. `git tag` shows what checkpoints exist.

Fix, in order of preference: if a `labN-complete` tag exists for a lab the student has actually finished, `git reset --hard labN-complete` is the cleanest fix and needs nothing from you beyond confirming the student is fine losing any uncommitted work since that tag. If no tag exists, `git stash` preserves uncommitted work while you sort out the rest. Avoid `git push --force` as a fix for anything, if the remote history genuinely needs to be rewritten, that is a conversation with the student about what they are willing to lose, not a quick command to run on their behalf.

## YAML or Python will not parse

Symptom: a script or playbook fails immediately with a parsing or indentation error, before it has done anything to a device.

Check: run the same validation command the labs teach students to run themselves.

```bash
python3 -c "import yaml; yaml.safe_load(open('file.yml'))"
python3 -m py_compile script.py
```

Both report the exact line and, for YAML, often the column where the file stopped making sense. You do not need to understand the semantic content of the file to fix this category of problem, you need to find the indentation or quoting mistake at the reported line, which is a Linux and text-editing skill, not a networking one.

Fix: correct the indentation or quoting at the reported line. If the reported line looks fine, check the line immediately above it, a missing colon or an unmatched bracket on the previous line frequently only surfaces as an error one line later.

## Ansible task fails on something that should be simple

Symptom: a read-only Ansible command, like gathering facts or running `show version`, fails with a privilege or "invalid input" style error.

Check: open the student's `inventory.yml` and confirm `ansible_become: true` and `ansible_become_method: enable` are both present under the `ceos` group's `vars`.

Fix: add or correct those two lines. This is by far the most common Ansible failure in these labs, and it is worth checking first before assuming the playbook logic itself is wrong.

## NETCONF or gNMI script fails with a namespace, path, or connection error

This category genuinely does require familiarity with the specific protocol, and is the one place in this course where a TA without that background should not spend more than a few minutes before pulling in an instructor. Two quick checks are worth doing first regardless:

```bash
nc -zv ceos1 830
nc -zv srl1 830
nc -zv srl1 57400
```

If the port is not reachable at all, the problem is the topology, not the script, redeploy `lab-net` and retry. If the port is reachable and the script still fails, that is the point to hand off to someone familiar with NETCONF or gNMI specifically, since the fix usually depends on the exact YANG model and namespace in play.

## Docker container name already in use

Symptom: `docker run --name batfish ...` or the NetBox compose stack fails to start with a message about a name already being in use.

Check: `docker ps -a` lists all containers, including stopped ones.

Fix: `docker rm -f batfish` (or the relevant container name), then retry the original command. This is safe, it does not touch anything containerlab is managing.

## GitHub Actions workflow will not run, or push is rejected

Symptom: a push that adds or modifies a file under `.github/workflows/` is rejected.

Check: the token's scopes, under the student's GitHub account, Settings, Developer settings, Personal access tokens. The `repo` scope from Lab 1 is not sufficient for workflow files, `workflow` scope is also required.

Fix: have the student add the `workflow` scope to their existing token, or generate a new token with both scopes and update their stored credentials.

## A hand-edited config snapshot breaks Batfish entirely, not just the intended line

Symptom: in Lab 5's Batfish task, a check that should only be affected by one intentional change instead fails in a way that suggests the whole snapshot did not parse.

Check: ask whether the student made a backup (`ceos1.cfg.bak`) before editing, the lab instructs them to. If they did, diff the two.

Fix: restore from the backup and redo the edit more carefully, adding the new lines without disturbing the surrounding syntax. If no backup exists, the student will need to regenerate the snapshot from the live device with the Ansible backup playbook from Task 9, then redo the intended edit.

# When to Escalate to a VM Snapshot Restore

Snapshot restore depends on staff availability outside this course and is not instant, so it should be the last resort, not a first response to a frustrated student. Reserve it for situations where the damage is genuinely outside the student's own recoverable files, for example:

- A `sudo rm -rf` or similar command was run against a path outside `~/labs`, `~/tools`, or `~/netbox-docker`.
- The VM's package management, networking, or Docker installation itself appears broken, not just the lab environment inside it.
- The student cannot log in at all, or the VM is unresponsive.

Before requesting a restore, collect and note down:

- What command the student believes caused the problem, in their own words, and the exact command if they still have it in their shell history (`history | tail -30`).
- The output of `pwd`, `ls -la /`, and `df -h`, gives a snapshot of what state the filesystem is actually in.
- Which lab and task the student was on.

This makes the restore request faster to act on and gives you something concrete to reference if the same failure shows up again with another student.

# Known Trouble Spots by Lab

This section is meant to be short and will grow. Add an entry here the first time a new problem type shows up in a live session, even briefly, expand it later.

Lab 1: the most common early confusion is students not realizing `sudo` is required for namespace and systemd operations but not for most git or Python commands, watch for permission-denied errors on the first lab.

Lab 2: `--cleanup` against `lab-net` is the single highest-impact mistake possible in this lab, see the Destroyed or Lost Topology State section above.

Lab 3: NETCONF namespace mismatches between vendors are the main source of confusing failures, see the NETCONF or gNMI section above.

Lab 4: missing `ansible_become` settings account for most Ansible failures, see the Ansible section above.

Lab 5: hand-edited `.cfg` snapshot files breaking Batfish's whole parse, and GitHub token scope issues on the Actions workflow push, are the two recurring problems, see their respective sections above.

# Maintaining This Guide

When you or another instructor resolves a problem that is not already covered above, add a short entry under the relevant category, or a new category if it does not fit an existing one. A rough entry is fine, structure and polish are secondary to the next TA being able to find it during a live session. Periodically fold repeated entries from Known Trouble Spots into the main Problems by Category section if they turn out not to be lab-specific.
