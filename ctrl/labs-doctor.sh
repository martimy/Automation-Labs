#!/usr/bin/env bash
#
# labs-doctor.sh
#
# A read-only health check for the INWK6312 lab environment. It does not
# fix anything and does not change any state, it only reports what it
# finds, so it is safe to run at any point in any lab, as many times as
# you like.
#
# Usage:
#   ./labs-doctor.sh            auto-detects the furthest-along lab
#   ./labs-doctor.sh 3          checks lab3 specifically, plus base checks
#
# Intended audience: students troubleshooting their own environment, and
# TAs or instructors who are not necessarily familiar with every tool in
# this course but need a fast first read on what is and is not working.

set -u

LABS_ROOT="${HOME}/labs"
PASS=0
WARN=0
FAIL=0

# ---------------------------------------------------------------------
# Output helpers. Falls back to plain text if the terminal has no color
# support, so this is safe to run from a TA's SSH session too.
# ---------------------------------------------------------------------
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    C_PASS="$(tput setaf 2)"
    C_WARN="$(tput setaf 3)"
    C_FAIL="$(tput setaf 1)"
    C_HEAD="$(tput bold)"
    C_RESET="$(tput sgr0)"
else
    C_PASS=""; C_WARN=""; C_FAIL=""; C_HEAD=""; C_RESET=""
fi

section() {
    echo ""
    echo "${C_HEAD}== $1 ==${C_RESET}"
}

pass() {
    echo "  ${C_PASS}[PASS]${C_RESET} $1"
    PASS=$((PASS + 1))
}

warn() {
    echo "  ${C_WARN}[WARN]${C_RESET} $1"
    WARN=$((WARN + 1))
}

fail() {
    echo "  ${C_FAIL}[FAIL]${C_RESET} $1"
    FAIL=$((FAIL + 1))
}

info() {
    echo "         $1"
}

have() {
    command -v "$1" >/dev/null 2>&1
}

# ---------------------------------------------------------------------
# Which lab to focus the lab-specific checks on. Defaults to the
# highest numbered lab folder that has been created, since Task 0 of
# each lab is what creates that folder in the first place.
# ---------------------------------------------------------------------
detect_current_lab() {
    local highest=0
    local n
    for n in 1 2 3 4 5; do
        [ -d "${LABS_ROOT}/lab${n}" ] && highest=$n
    done
    echo "$highest"
}

CURRENT_LAB="${1:-$(detect_current_lab)}"

echo "${C_HEAD}INWK6312 Environment Check${C_RESET}"
echo "Run from: $(pwd)"
echo "Home: ${HOME}"
if [ "$CURRENT_LAB" -eq 0 ] 2>/dev/null; then
    echo "Detected lab: none found yet, running base checks only"
else
    echo "Detected lab: lab${CURRENT_LAB} (pass a number 1-5 to override)"
fi

# ---------------------------------------------------------------------
# Base folder structure
# ---------------------------------------------------------------------
section "Folder Structure"

if [ -d "$LABS_ROOT" ]; then
    pass "~/labs exists"
else
    fail "~/labs does not exist, nothing else in this script will work until it does"
fi

if [ -d "${HOME}/tools" ]; then
    pass "~/tools exists (instructor tools clone)"
elif [ -d "${LABS_ROOT}/tools" ]; then
    pass "~/labs/tools exists"
else
    warn "no tools folder found at ~/tools or ~/labs/tools, expected from Lab 3 onward"
fi

for script in nc_wrapper.sh netconf_tool.py gnmi_tool.py devicelib.py; do
    found=""
    for base in "${HOME}/tools" "${LABS_ROOT}/tools"; do
        if [ -f "${base}/${script}" ]; then
            found="${base}/${script}"
            break
        fi
    done
    if [ -n "$found" ]; then
        if [ "${script##*.}" = "sh" ] && [ ! -x "$found" ]; then
            warn "$script found but not executable ($found), run: chmod +x $found"
        else
            pass "$script found"
        fi
    else
        info "$script not found (expected from Lab 3 onward, skip if not there yet)"
    fi
done

# ---------------------------------------------------------------------
# Python virtual environment
# ---------------------------------------------------------------------
section "Python Environment"

if [ -d "${LABS_ROOT}/.velab" ]; then
    pass "virtual environment folder ~/labs/.velab exists"
else
    warn "no ~/labs/.velab found, expected from Lab 2 onward"
fi

if [ -n "${VIRTUAL_ENV:-}" ]; then
    pass "a virtual environment is currently active ($VIRTUAL_ENV)"
else
    warn "no virtual environment is currently active, run: source ~/labs/.velab/bin/activate"
fi

if have python3; then
    pass "python3 available ($(python3 --version 2>&1))"
    if [ -n "${VIRTUAL_ENV:-}" ]; then
        for pkg in netmiko ncclient pygnmi ansible pynetbox pybatfish; do
            if python3 -c "import ${pkg}" >/dev/null 2>&1; then
                pass "python package '${pkg}' importable"
            else
                info "python package '${pkg}' not importable (fine if you have not reached the lab that needs it)"
            fi
        done
    fi
else
    fail "python3 not found on PATH"
fi

# ---------------------------------------------------------------------
# Git repository
# ---------------------------------------------------------------------
section "Git Repository"

if [ -d "${LABS_ROOT}/.git" ]; then
    pass "~/labs is a git repository"

    cd "$LABS_ROOT" || exit 1

    dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [ "$dirty" -eq 0 ]; then
        pass "working tree is clean"
    else
        warn "$dirty file(s) modified or untracked, run 'git status' for detail"
    fi

    if git remote get-url origin >/dev/null 2>&1; then
        pass "remote 'origin' is configured"
    else
        fail "no 'origin' remote configured, push will not work"
    fi

    branch=$(git branch --show-current 2>/dev/null)
    info "current branch: ${branch:-unknown}"

    local_tags=$(git tag -l 'lab*-complete' 2>/dev/null)
    if [ -n "$local_tags" ]; then
        pass "found checkpoint tag(s): $(echo "$local_tags" | tr '\n' ' ')"
    else
        info "no lab checkpoint tags found yet (lab1-complete etc.), expected after finishing a lab's commit task"
    fi

    if [ -n "$local_tags" ] && git remote get-url origin >/dev/null 2>&1; then
        remote_tags=$(git ls-remote --tags origin 2>/dev/null | awk -F'refs/tags/' '{print $2}' | grep -E '^lab[0-9]-complete$')
        for t in $local_tags; do
            if echo "$remote_tags" | grep -qx "$t"; then
                pass "tag $t is pushed to origin"
            else
                warn "tag $t exists locally but not on origin, run: git push origin $t"
                info "a local-only tag will not survive a fresh clone if this repository needs to be re-cloned"
            fi
        done
    fi
else
    fail "~/labs is not a git repository, expected from Lab 1 onward"
fi

# ---------------------------------------------------------------------
# .gitignore sanity
# ---------------------------------------------------------------------
section "gitignore Checks"

if [ -f "${LABS_ROOT}/.gitignore" ]; then
    pass ".gitignore exists"
    for pattern in ".velab" ".env" "clab-"; do
        if grep -qF "$pattern" "${LABS_ROOT}/.gitignore" 2>/dev/null; then
            pass "'.gitignore' appears to cover '${pattern}'"
        else
            warn "'.gitignore' does not appear to mention '${pattern}', double check this is intentional"
        fi
    done
else
    fail "no ~/labs/.gitignore found"
fi

# ---------------------------------------------------------------------
# Containerlab and the network topology
# ---------------------------------------------------------------------
section "Network Topology"

if have containerlab; then
    pass "containerlab is installed ($(containerlab version 2>/dev/null | head -1))"
else
    fail "containerlab not found on PATH"
fi

TOPO_FILE=""
for candidate in "${LABS_ROOT}/topology/lab-net.clab.yml" "${LABS_ROOT}/lab2/topology/lab-net.clab.yml"; do
    if [ -f "$candidate" ]; then
        TOPO_FILE="$candidate"
        break
    fi
done

if [ -n "$TOPO_FILE" ]; then
    pass "topology file found: $TOPO_FILE"
    if command -v python3 >/dev/null 2>&1; then
        if python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$TOPO_FILE" >/dev/null 2>&1; then
            pass "topology file is valid YAML"
        else
            fail "topology file failed to parse as YAML, run: python3 -c \"import yaml; yaml.safe_load(open('$TOPO_FILE'))\" to see the error"
        fi
    fi
else
    warn "no lab-net.clab.yml found under ~/labs/topology or ~/labs/lab2/topology"
fi

SAVED_STATE=""
for candidate in "${LABS_ROOT}/topology/clab-lab-net" "${LABS_ROOT}/lab2/topology/clab-lab-net"; do
    if [ -d "$candidate" ]; then
        SAVED_STATE="$candidate"
        break
    fi
done

if [ -n "$SAVED_STATE" ]; then
    node_count=$(find "$SAVED_STATE" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')
    if [ "$node_count" -gt 0 ]; then
        pass "saved topology state found at $SAVED_STATE ($node_count node folder(s))"
    else
        warn "saved topology state folder exists but is empty: $SAVED_STATE"
    fi
else
    warn "no saved topology state folder found, this is expected only before the first 'containerlab save'"
fi

if have docker; then
    running=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E '^clab-lab-net-' )
    if [ -n "$running" ]; then
        pass "topology appears to be deployed, running containers:"
        echo "$running" | sed 's/^/         /'
    else
        info "no clab-lab-net-* containers currently running, topology may simply be destroyed right now, not necessarily a problem"
    fi
else
    fail "docker not found on PATH"
fi

# ---------------------------------------------------------------------
# Lab 5 extras: NetBox and Batfish
# ---------------------------------------------------------------------
if [ "$CURRENT_LAB" -ge 5 ] 2>/dev/null; then
    section "Lab 5 Extras: NetBox and Batfish"

    if [ -d "${HOME}/netbox-docker" ]; then
        pass "~/netbox-docker exists"
        if have docker; then
            nb_running=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i netbox)
            if [ -n "$nb_running" ]; then
                pass "NetBox containers running:"
                echo "$nb_running" | sed 's/^/         /'
            else
                info "no NetBox containers currently running, start with: cd ~/netbox-docker && docker compose up -d"
            fi
        fi
    else
        warn "~/netbox-docker not found"
    fi

    ENV_FILE=""
    for candidate in "${LABS_ROOT}/lab5/.env" "${HOME}/netbox-docker/.env"; do
        [ -f "$candidate" ] && ENV_FILE="$candidate"
    done
    if [ -n "$ENV_FILE" ]; then
        pass "NetBox token file found: $ENV_FILE"
        if git -C "$LABS_ROOT" check-ignore -q "$ENV_FILE" 2>/dev/null; then
            pass "$ENV_FILE is correctly ignored by git"
        else
            fail "$ENV_FILE is NOT ignored by git, this file holds a secret, add it to .gitignore before committing anything"
        fi
    else
        info "no .env file found yet (expected once Task 0 of Lab 5 is complete)"
    fi

    if have docker; then
        bf_running=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -x batfish)
        bf_stopped=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -x batfish)
        if [ -n "$bf_running" ]; then
            pass "batfish container is running"
        elif [ -n "$bf_stopped" ]; then
            warn "a batfish container exists but is not running, if 'docker run --name batfish ...' fails with 'name already in use', run: docker rm -f batfish"
        else
            info "no batfish container found, expected before Task 9 is started"
        fi
    fi
fi

# ---------------------------------------------------------------------
# Disk space
# ---------------------------------------------------------------------
section "Disk Space"

if have df; then
    avail_pct=$(df -P "$HOME" 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $5}')
    if [ -n "$avail_pct" ]; then
        if [ "$avail_pct" -ge 90 ]; then
            fail "home partition is ${avail_pct}% full, run 'df -h' and clear space before continuing"
        elif [ "$avail_pct" -ge 75 ]; then
            warn "home partition is ${avail_pct}% full, worth keeping an eye on"
        else
            pass "home partition is ${avail_pct}% full"
        fi
    else
        info "could not determine disk usage"
    fi
fi

# ---------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------
section "Summary"
echo "  ${C_PASS}${PASS} passed${C_RESET}, ${C_WARN}${WARN} warning(s)${C_RESET}, ${C_FAIL}${FAIL} failure(s)${C_RESET}"
echo ""
echo "This script only reports what it finds, it does not change anything."
echo "For what a specific FAIL or WARN means and how to fix it, see the"
echo "INWK6312 Student Guide or the Instructor Troubleshooting Guide."

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
