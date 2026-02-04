#!/usr/bin/env bash
set -euo pipefail

# Initializes the canonical secrets directory with safe permissions.
# Run as root (recommended): sudo bash ops/init-secrets-path.sh

BASE="/etc/heimserver/secrets"

mkdir -p "$BASE"
chmod 0700 "$BASE"

mkdir -p "$BASE/wireguard/peers"
mkdir -p "$BASE/pki"

chmod 0700 "$BASE/wireguard" "$BASE/wireguard/peers" "$BASE/pki"

cat <<EOF
Initialized:
  $BASE
  $BASE/wireguard/peers
  $BASE/pki

Reminder:
  Put private keys here (NOT in Git).
EOF

exit 0
