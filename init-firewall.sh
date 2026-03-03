#!/usr/bin/env bash
# Firewall initialization for Claude Code Sandbox
# Based on the official Anthropic init-firewall.sh
#
# Only allows connections to:
#   - DNS, SSH, Localhost
#   - Anthropic API + telemetry (Sentry, Statsig)
#   - GitHub (web, API, releases)
#   - Common package registries (npm, PyPI, Maven, crates.io, Go proxy,
#     RubyGems, Packagist, NuGet, Docker Hub)
#   - VS Code Marketplace
# See allowed-domains.txt for the full list.
# Blocks everything else.
set -euo pipefail
IFS=$'\n\t'

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Must be run as root (via sudo)." >&2
    exit 1
fi

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

if [ "${FIREWALL_ENABLED:-true}" != "true" ]; then
    echo "=== Firewall DISABLED (FIREWALL_ENABLED=${FIREWALL_ENABLED:-}) ==="
    exit 0
fi

echo "=== Firewall initialization ==="

# Only flush the filter table.
# Do NOT touch the nat table — Docker DNS (127.0.0.11) depends on it.
iptables -F
iptables -X
ipset destroy allowed_ips 2>/dev/null || true

# Base rules: DNS, SSH, Loopback
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A INPUT -p tcp --sport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# ipset for allowed IPs
ipset create allowed_ips hash:net

# Load GitHub IPs from official API
echo "Loading GitHub IP ranges..."
gh_ranges=$(curl -fsSL --max-time 15 https://api.github.com/meta 2>/dev/null || echo "{}")
if echo "$gh_ranges" | jq -e '.web' >/dev/null 2>&1; then
    echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' 2>/dev/null | while read -r cidr; do
        if [[ "$cidr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
            ipset add allowed_ips "$cidr" 2>/dev/null || true
        fi
    done
    echo "  GitHub IPs loaded"
else
    echo "  WARNING: Could not load GitHub IPs"
fi

# Helper function: Resolve domain with fallback to public DNS servers
resolve_domain() {
    local domain="$1"
    local ips=""
    # 1st attempt: getent ahosts (follows CNAME chains via system resolver)
    ips=$(getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | grep -E '^[0-9]+\.' | sort -u || true)
    # 2nd attempt: dig via local DNS
    if [ -z "$ips" ]; then
        ips=$(dig +short A "$domain" 2>/dev/null | grep -E '^[0-9]+\.' || true)
    fi
    # 3rd attempt: dig via Google DNS (for CNAME chains that cannot be resolved locally)
    if [ -z "$ips" ]; then
        ips=$(dig +short A "$domain" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.' || true)
    fi
    # 4th attempt: dig via Cloudflare DNS
    if [ -z "$ips" ]; then
        ips=$(dig +short A "$domain" @1.1.1.1 2>/dev/null | grep -E '^[0-9]+\.' || true)
    fi
    echo "$ips"
}

# Read allowed domains from file and whitelist them
DOMAINS_FILE="/usr/local/bin/allowed-domains.txt"
if [ ! -f "$DOMAINS_FILE" ]; then
    echo "ERROR: $DOMAINS_FILE not found" >&2
    exit 1
fi

while IFS= read -r domain || [ -n "$domain" ]; do
    domain=$(echo "$domain" | sed 's/#.*//' | xargs)
    [ -z "$domain" ] && continue
    ips=$(resolve_domain "$domain")
    for ip in $ips; do
        ipset add allowed_ips "$ip/32" 2>/dev/null || true
    done
    if [ -n "$ips" ]; then
        echo "  $domain resolved"
    else
        echo "  WARNING: Could not resolve $domain"
    fi
done < "$DOMAINS_FILE"

# Detect and allow host network
HOST_IP=$(ip route | grep default | head -1 | awk '{print $3}')
if [ -n "$HOST_IP" ]; then
    HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
    echo "Host network: $HOST_NETWORK"
    iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
    iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT
fi

# Default policies: block everything
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow whitelisted IPs
iptables -A OUTPUT -m set --match-set allowed_ips dst -j ACCEPT

# Reject everything else (REJECT for fast feedback instead of DROP timeout)
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo "=== Firewall active ==="

# Verification
echo "Verifying..."
if curl -sf --max-time 5 https://example.com >/dev/null 2>&1; then
    echo "  WARNING: example.com is reachable (should be blocked)"
else
    echo "  [OK] example.com blocked"
fi

if curl -sf --max-time 10 https://api.github.com/zen >/dev/null 2>&1; then
    echo "  [OK] api.github.com reachable"
else
    echo "  WARNING: api.github.com not reachable"
fi

if curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://api.anthropic.com 2>/dev/null | grep -qE '^[0-9]+$'; then
    echo "  [OK] api.anthropic.com reachable"
else
    echo "  WARNING: api.anthropic.com not reachable"
fi

echo "=== Firewall initialization complete ==="
