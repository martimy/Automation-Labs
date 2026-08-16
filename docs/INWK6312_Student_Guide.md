---
title: INWK6312 Student Lab Guide, 
subtitle: Avoiding and Recovering from Common Mistakes
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


This guide is not part of any single lab. It collects the mistakes students most commonly make while working through the INWK6312 labs, why they happen, and what to do if they happen to you. Skim it once before Lab 1, then come back to it whenever something breaks.

This is a living document. If you hit a problem that is not covered here, tell your instructor, it likely means this guide needs an update, not that you did something unusually wrong.

# Before You Start Any Lab, Five Habits Worth Building

1. Chain a `cd` with whatever comes after it, using `&&`, whenever the next command depends on being in the right place. `cd ~/labs/lab3 && nano script.py` fails loudly if the `cd` fails. `cd ~/labs/lab3` on its own line followed by `nano script.py` on the next line will happily create `script.py` in the wrong folder if the `cd` silently failed, and you may not notice until a later step.
2. Check a file before you run it. For YAML: `python3 -c "import yaml; yaml.safe_load(open('file.yml'))"`. For Python: `python3 -m py_compile script.py`. For a shell script: `bash -n script.sh`. For an Ansible playbook: `ansible-playbook -i inventory.yml playbook.yml --syntax-check`. All four take a few seconds and turn an invisible whitespace or syntax mistake into a specific, readable error message instead of a confusing failure two commands later.
3. Tag the end of every lab: `git tag labN-complete`. This is your personal undo button. If a later lab goes badly wrong, `git reset --hard labN-complete` returns your repository to exactly that known-good state, no one else needs to be involved.
4. Read error messages before retyping the command. Most of what looks like a mysterious failure is a specific, plain-English sentence telling you exactly what went wrong, permission denied, file not found, already exists. The Quick Reference table at the end of this guide maps the most common ones to their fix.
5. Know the difference between a mess you can fix yourself and damage to the VM itself. Almost everything in these labs falls into the first category. If you are ever unsure which one you are looking at, stop and ask rather than trying increasingly drastic commands to fix it.

# Mistakes That Are Easy to Make, and How to Avoid Them

## Typing a path wrong, especially a missing `~`

`mkdir -p /labs/lab5` (no `~`) creates a folder at the filesystem root, which needs `sudo` and is not where anything else expects to find your files. `mkdir -p labs/lab5` (no leading `/` or `~`) creates it relative to wherever you currently are, which is fine if you happen to be in your home directory and confusing if you are not.

Avoid it: use the `cd && command` pattern from habit 1 above, and prefer typing `~/labs/...` in full for anything that creates or deletes files, rather than relying on your current directory.

Recover from it: `pwd` tells you where you are. `find ~ -maxdepth 4 -newer /tmp -type d 2>/dev/null` can help you spot a folder you just created somewhere unexpected. A stray folder created by a wrong path is almost always harmless on its own, the risk is `git add`ing it later without noticing, so check `git status` before every commit.

## Destructive commands run against the wrong thing

The single most consequential version of this in these labs is `containerlab destroy --cleanup`. It is correct for the disposable single-node topologies early in Lab 2, and it is wrong for `lab-net`, the topology every lab after that depends on, because it deletes the saved configuration you would otherwise recover with a plain redeploy.

Avoid it: never add `--cleanup` when destroying `lab-net`. If a lab's instructions show a destroy command without `--cleanup`, that absence is deliberate, not an omission.

Recover from it: if you already destroyed `lab-net` with `--cleanup` and lost the saved state, tell your instructor rather than trying to hand-reconstruct the configuration from memory, the Appendix configuration tables in each lab can help rebuild it, but it is faster for your instructor to confirm what you actually lost first.

Other destructive commands worth double-checking before you run them: `git push --force` (never use this in these labs, it can destroy shared history), `git branch -D` (deletes a branch, including unmerged work on it), and `rm -rf` on anything (always confirm the path with `pwd` and `ls` first, especially if you are about to use `sudo`).

## Whitespace and indentation problems in YAML and Python

YAML and Python both use indentation to mean something. A file that looks correct to your eye can still be broken if a tab snuck in next to spaces, or if a line got re-indented when you pasted it. This is one of the most common causes of a confusing failure, because the symptom, a parsing error or an `IndentationError`, often looks unrelated to what you actually did wrong.

Avoid it: validate before you run, as in habit 2 above. In VS Code, turn on Render Whitespace (View, Render Whitespace) when editing YAML or Python, it makes mixed tabs and trailing spaces visible instead of invisible.

Recover from it: read the line number in the error message, it is almost always exactly right. `python3 -c "import yaml; yaml.safe_load(open('file.yml'))"` will point at the specific line and column where YAML parsing broke. If the error makes no sense at the line it names, check the line just above it, a missing colon or an extra space on the previous line often only shows up as an error one line later.

## Quotes that do not match

If you ever copy a command or a piece of code and get a shell error about an unexpected token, or Python complaining about a string that never ends, check whether the quote characters are actually straight quotes (`"` and `'`) and not curly ones (` " ` or `'`). Curly quotes are usually introduced by whatever you copied the text through, not by anything you did.

Avoid it: when typing a command yourself, use your own keyboard's quote key rather than copying quote characters from a rendered PDF or web page if you can help it.

Recover from it: retype just the quote characters in the offending line by hand.

## Re-running a command that assumes a clean slate

Some commands fail, with a normal and expected error, if you run them a second time without undoing the first run. `containerlab deploy` on a topology that is already up, `ip netns add` on a namespace that already exists, `docker run --name X` when a container named `X` already exists, all report "already exists" rather than doing anything destructive.

Avoid it: read the error, it is telling you exactly what state you are already in.

Recover from it: destroy or remove the existing thing first, then retry. For Docker specifically: `docker rm -f <name>` before rerunning `docker run --name <name> ...`.

## A merge conflict that feels stuck

Git conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`) can be intimidating the first time you see them, and it is tempting to start deleting things at random to make them go away.

Avoid it: read both sides of the conflict before editing anything, decide deliberately which lines you want to keep, then remove the markers.

Recover from it: `git merge --abort` cancels the merge entirely and returns you to exactly how things looked before you attempted it. You lose nothing by using this if you want to start over. Before staging a file you just resolved, run `bash -n` on it if it is a script, or otherwise reread it once, to confirm no stray conflict markers were left behind.

# If Something Breaks, Where to Start

Work through these roughly in order, they are ordered from fastest and most self-contained to most involved.

1. Read the actual error message. Check the Quick Reference table below, your exact error is probably in it.
2. Re-run the validation check for whatever kind of file is involved, YAML, Python, a shell script, or a playbook, as in habit 2 above.
3. Check `git status` and `pwd`. A large fraction of "nothing is working" turns out to be "I am not where I think I am."
4. If it is contained to one lab and you have a checkpoint tag from a previous lab, consider `git reset --hard labN-complete` to start the current lab's git-tracked work over cleanly. This does not undo damage outside your repository, such as a broken containerlab topology.
5. If the network topology itself is in a bad state, redeploy it. `sudo containerlab destroy -t ~/labs/topology/lab-net.clab.yml` (no `--cleanup`) followed by `sudo containerlab deploy -t ~/labs/topology/lab-net.clab.yml` restores it from the saved configuration.
6. If none of the above resolves it, or you are not sure which of the above applies, ask your instructor. This is a new set of labs, and telling us what actually went wrong is genuinely useful, you are very unlikely to be the only student who hit it.

# When to Stop and Ask for Help Immediately

Stop and ask rather than continuing to try commands if:

- You deleted something outside your `~/labs` folder, or ran a command with `sudo` against a path you are not sure about.
- You are not sure whether a command you are about to run is reversible.
- The VM itself seems unstable, extremely slow, unresponsive, or you suspect something outside the lab environment is affected.

Restoring a VM from a snapshot depends on staff availability and is not instant, so the goal of this guide is to help you avoid ever needing one. When in doubt, asking costs you a few minutes. Guessing wrong can cost a lot more.

# Quick Reference, Error Message to Likely Cause

| What you see | Likely cause | What to do |
|---|---|---|
| `Permission denied` | Missing `sudo`, or trying to write to a system location as a normal user | Add `sudo` if the step calls for it, or check you are writing inside your own home directory |
| `command not found` | Wrong directory, virtual environment not activated, or a typo in the command name | Check `pwd`, check `which python3`, confirm `source .velab/bin/activate` was run |
| `No such file or directory` | Wrong path, missing `~`, or the file genuinely has not been created yet | Check `pwd` and `ls`, reread the step to confirm you created the file first |
| `fatal: not a git repository` | You are outside `~/labs` | `cd ~/labs` and retry |
| `fatal: could not read Username` or an authentication prompt on `git push` | Your personal access token is missing, expired, or lacks the required scope | Regenerate the token on GitHub with the scope the lab specifies, `repo` or `repo` plus `workflow` |
| `error: src refspec main does not match any` | You tried to push before making a first commit | `git commit` before `git push` |
| `already exists` from `containerlab deploy`, `ip netns add`, or `docker run` | You are re-running a command against something that is already up | Destroy or remove the existing thing first, then retry |
| `yaml.scanner.ScannerError` or `yaml.parser.ParserError` | Indentation or structural problem in a YAML file | Fix the line number named in the error, check the line above it too |
| `IndentationError` or `SyntaxError` in Python | Mixed tabs and spaces, or a typo from copy-paste | Run `python3 -m py_compile file.py` and fix the line it names |
| Shell error mentioning an unexpected `"` or a string that "never closes" | Curly quotes instead of straight quotes | Retype the quote characters by hand |
| `error: patch does not apply` or `error: does not match index` | The file has changed since a diff or patch was generated against it | Use the full corrected file instead of the patch, or re-generate the diff against your current file |
| Ansible task fails with a privilege or "invalid input" style error on a simple read-only command | `ansible_become` or `ansible_become_method` missing or wrong in the inventory | Check those two variables against the lab's inventory example |
| `embedded git repository` warning from `git add` | `**/clab-*/` is missing from `.gitignore` | Add it to `.gitignore`, do not force-add the embedded repository |
| Batfish check fails in a way that does not match what you expected to have changed | A hand-edit to a `.cfg` snapshot file broke something elsewhere in the file, not just the line you meant to change | Compare against your `.bak` copy of the file, or restore it and redo the edit more carefully |
