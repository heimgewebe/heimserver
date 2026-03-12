#!/usr/bin/env bash
set -euo pipefail

# Docs Relations Guard
# Thin wrapper around check_repo_index_consistency.py to align with blueprint terminology

log() { printf "INFO: %s\n" "$*"; }

python3 scripts/ci/check_repo_index_consistency.py

log "Docs relations checks passed."
