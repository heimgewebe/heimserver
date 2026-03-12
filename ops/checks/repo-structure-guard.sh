#!/usr/bin/env bash
set -euo pipefail

# Repo Structure Guard
# Verifies the presence of core artifacts, the `docs/_generated/` directory,
# and the basic parseability of `repo.meta.yaml`.

log() { printf "INFO: %s\n" "$*"; }
fail() { printf "FAIL: %s\n" "$*" >&2; exit 1; }

# 1. Check core artifacts
for file in "repo.meta.yaml" "AGENTS.md" "docs/index.md" "agent-policy.yaml"; do
    if [ ! -f "$file" ]; then
        fail "Missing core artifact: $file"
    fi
done

# 2. Check docs/_generated directory
if [ ! -d "docs/_generated" ]; then
    fail "Missing generated docs directory: docs/_generated/"
fi

# 3. Check basic parseability of repo.meta.yaml
if ! grep -q "^repo_name:" repo.meta.yaml; then
    fail "repo.meta.yaml does not contain a 'repo_name' key. Is it valid YAML?"
fi

log "Repo structure checks passed."
