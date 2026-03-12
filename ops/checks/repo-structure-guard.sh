#!/usr/bin/env bash
# ops/checks/repo-structure-guard.sh
# Verifies the required core structural elements of the intelligent repo.

set -e

echo "Starting Repo Structure Guard..."

ERRORS=0

check_file() {
    if [ ! -f "$1" ]; then
        echo "❌ Missing required file: $1"
        ERRORS=$((ERRORS + 1))
    else
        echo "✅ Found: $1"
    fi
}

check_file "repo.meta.yaml"
check_file "agent-policy.yaml"
check_file "docs/index.md"
check_file "docs/_generated/doc-index.md"

if [ $ERRORS -gt 0 ]; then
    echo "❌ Repo Structure Guard failed with $ERRORS errors."
    exit 1
else
    echo "✅ Repo Structure Guard passed."
    exit 0
fi
