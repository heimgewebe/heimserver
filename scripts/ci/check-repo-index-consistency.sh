#!/usr/bin/env bash
set -euo pipefail

# Check Repo Index Consistency
# Verifies:
# 1. manifest/repo-index.yaml matches file system
# 2. Frontmatter exists and is valid (id, status, role, last_reviewed)
# 3. IDs are unique

echo "Starting Repo Index Consistency Check..."

python3 - <<'EOF'
import os
import re
import sys

MANIFEST_PATH = 'manifest/repo-index.yaml'

def load_manifest():
    data = {'zones': {}, 'checks': []}
    current_zone = None
    in_checks = False

    if not os.path.exists(MANIFEST_PATH):
        print(f"Error: Manifest not found at {MANIFEST_PATH}")
        sys.exit(1)

    with open(MANIFEST_PATH, 'r', encoding='utf-8') as f:
        for line in f:
            stripped = line.strip()
            if not stripped or stripped.startswith('#'):
                continue

            if stripped == 'zones:':
                in_checks = False
                continue
            elif stripped == 'checks:':
                in_checks = True
                continue

            if in_checks:
                if stripped.startswith('- '):
                    data['checks'].append(stripped[2:])
            else:
                if line.startswith('  ') and not line.startswith('    ') and stripped.endswith(':'):
                    zone_name = stripped[:-1]
                    current_zone = zone_name
                    data['zones'][current_zone] = {'path': '', 'canonical_docs': []}
                elif line.startswith('    path:'):
                    path = stripped.split(':', 1)[1].strip()
                    if current_zone:
                        data['zones'][current_zone]['path'] = path
                elif line.startswith('      - '):
                    doc = stripped[2:]
                    if current_zone:
                        data['zones'][current_zone]['canonical_docs'].append(doc)
    return data

def parse_frontmatter(filepath):
    if not os.path.exists(filepath):
        return None
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # CRLF tolerant
    match = re.match(r'^---\r?\n(.*?)\r?\n---\r?(?:\n|$)', content, re.DOTALL)
    if not match:
        return None

    fm_content = match.group(1)
    data = {}
    current_list_key = None

    for line in fm_content.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith('#'):
            continue

        # Check list item
        if stripped.startswith('- '):
             if current_list_key:
                 val = stripped[2:].strip()
                 # Unquote
                 if (val.startswith('"') and val.endswith('"')) or (val.startswith("'") and val.endswith("'")):
                    val = val[1:-1]
                 data[current_list_key].append(val)
             continue

        if ':' in line:
            key, val = line.split(':', 1)
            key = key.strip()
            val = val.strip()

            if not val:
                current_list_key = key
                data[key] = []
            elif val.startswith('[') and val.endswith(']'):
                # Inline list
                if val == '[]':
                     data[key] = []
                else:
                     items = [x.strip() for x in val[1:-1].split(',')]
                     clean_items = []
                     for item in items:
                         if (item.startswith('"') and item.endswith('"')) or (item.startswith("'") and item.endswith("'")):
                             clean_items.append(item[1:-1])
                         else:
                             clean_items.append(item)
                     data[key] = clean_items
                current_list_key = None
            else:
                # Plain value
                if (val.startswith('"') and val.endswith('"')) or (val.startswith("'") and val.endswith("'")):
                    val = val[1:-1]
                data[key] = val
                current_list_key = None

    return data

def main():
    manifest = load_manifest()
    zones = manifest.get('zones', {})

    errors = []
    seen_ids = {}

    print(f"Checking {len(zones)} zones...")

    for zone_name, zone_data in zones.items():
        base_path = zone_data.get('path', '')
        docs = zone_data.get('canonical_docs', [])

        for doc in docs:
            filepath = os.path.join(base_path, doc)

            # 1. Check file existence
            if not os.path.exists(filepath):
                errors.append(f"File missing: {filepath} (listed in {zone_name})")
                continue

            # 2. Check Frontmatter
            fm = parse_frontmatter(filepath)
            if fm is None:
                errors.append(f"Missing or invalid frontmatter: {filepath}")
                continue

            # 3. Check ID uniqueness and presence
            doc_id = fm.get('id')
            if not doc_id:
                errors.append(f"Missing 'id' in frontmatter: {filepath}")
            else:
                if doc_id in seen_ids:
                    errors.append(f"Duplicate ID '{doc_id}': {filepath} and {seen_ids[doc_id]}")
                else:
                    seen_ids[doc_id] = filepath

            # 4. Check status
            if 'status' not in fm:
                 errors.append(f"Missing 'status' in frontmatter: {filepath}")

            # 5. Check role
            if 'role' not in fm:
                 errors.append(f"Missing 'role' in frontmatter: {filepath}")

            # 6. Check last_reviewed format
            reviewed = fm.get('last_reviewed')
            if not reviewed:
                 errors.append(f"Missing 'last_reviewed' in frontmatter: {filepath}")
            elif not re.match(r'^\d{4}-\d{2}-\d{2}$', str(reviewed)):
                 errors.append(f"Invalid 'last_reviewed' format (expected YYYY-MM-DD): {filepath} ({reviewed})")

    # Check 'checks' existence
    checks = manifest.get('checks', [])
    for check in checks:
        if not os.path.exists(check):
             errors.append(f"Check script missing: {check}")

    if errors:
        print("\n❌ Consistency Check Failed with following errors:")
        for err in errors:
            print(f" - {err}")
        sys.exit(1)
    else:
        print("\n✅ All checks passed. Repo index is consistent.")
        sys.exit(0)

if __name__ == "__main__":
    main()
EOF
