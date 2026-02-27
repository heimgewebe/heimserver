#!/usr/bin/env bash
set -euo pipefail

# Check Repo Index Consistency
# Verifies:
# 1. manifest/repo-index.yaml matches file system
# 2. Frontmatter exists and is valid (id, status, role, last_reviewed)
# 3. IDs are unique
# 4. Dependency graph integrity

# Determine the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Call the Python version of the check
python3 "${SCRIPT_DIR}/check_repo_index_consistency.py"
