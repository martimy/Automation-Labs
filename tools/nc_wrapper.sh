#!/bin/bash
# nc_wrapper.sh
# Usage: ./nc_wrapper.sh <host> [netconf-console2 options...]

# ─── Credential Store ─────────────────────────────────────────────────────────
# Format: HOST|PORT|USERNAME|PASSWORD
CREDENTIALS=(
    "ceos1|830|admin|admin"
    "ceos2|830|admin|admin"
    "srl1|830|admin|NokiaSrl1!"
)

# ─── Credential lookup ────────────────────────────────────────────────────────
TARGET_HOST="$1"
shift

for entry in "${CREDENTIALS[@]}"; do
    IFS='|' read -r h p u pw <<< "$entry"
    if [[ "$h" == "$TARGET_HOST" ]]; then
        netconf-console2 --host "$h" --port "$p" -u "$u" -p "$pw" "$@"
        exit $?
    fi
done

echo "Error: No credentials found for host '$TARGET_HOST'"
exit 1
