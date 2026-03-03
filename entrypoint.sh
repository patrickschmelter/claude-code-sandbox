#!/usr/bin/env bash
# Entrypoint: Set up firewall as root, then switch to node user
set -euo pipefail

# Read FIREWALL_ENABLED from .env (takes precedence because environment
# variables are often not passed correctly through sudo/devcontainer)
for _envfile in /workspace/claude/.env /workspace/.env; do
    if [ -f "$_envfile" ]; then
        _val=$(grep '^FIREWALL_ENABLED=' "$_envfile" 2>/dev/null | tail -1 | cut -d= -f2-)
        if [ -n "$_val" ]; then
            FIREWALL_ENABLED="$_val"
            break
        fi
    fi
done

if [ "${FIREWALL_ENABLED:-true}" = "true" ]; then
    /usr/local/bin/init-firewall.sh
else
    echo "=== Firewall DISABLED (FIREWALL_ENABLED=$FIREWALL_ENABLED) ==="
fi

# Drop all capabilities and continue as node user
exec gosu node "$@"
