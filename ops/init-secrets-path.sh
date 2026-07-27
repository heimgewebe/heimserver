#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "Blocked: Heimserver is retired; reintroduce this script only through a new Bureau task and service-bound infra contract" >&2
exit 2

# Historical implementation preserved for reference. This file is unconditionally blocked while the repository is retired.

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
