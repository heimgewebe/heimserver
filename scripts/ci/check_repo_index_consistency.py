#!/usr/bin/env python3
import os
import sys
import re

# Ensure we can import from scripts/lib
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from scripts.lib.docmeta import load_repo_index, parse_frontmatter, normalize_path, validate_repo_relative_path, MANIFEST_PATH, ALLOWED_ROLES, ALLOWED_STATUS, ALLOWED_CANONICALITY, ALLOWED_DOC_TYPES, ALLOWED_DOC_ROLES, ALLOWED_REFERENCE_POLICIES

def main():
    print("Starting Repo Index Consistency Check...")

    if not os.path.exists(MANIFEST_PATH):
        print(f"Error: Manifest not found at {MANIFEST_PATH}")
        sys.exit(1)

    try:
        manifest = load_repo_index(MANIFEST_PATH)
    except Exception as e:
        print(f"Error loading manifest: {e}")
        sys.exit(1)

    zones = manifest.get('zones', {})
    errors = []
    seen_ids = {}

    # Store all canonical docs for dependency verification
    # Key: doc_id (unique), Value: filepath (relative to root)
    # Also maintain a map for filename lookups (which might be ambiguous, so list of paths)
    docs_by_id = {}
    docs_by_filename = {}

    print(f"Checking {len(zones)} zones...")

    # First pass: Collect all docs and check basics
    for zone_name, zone_data in zones.items():
        base_path = zone_data.get('path', '')
        docs = zone_data.get('canonical_docs', [])

        # Security check: Base path must be safe
        try:
            base_path = validate_repo_relative_path(base_path)
        except ValueError as e:
            errors.append(f"Invalid zone path '{base_path}': {e}")
            continue

        for doc_filename in docs:
            # Security check: Filename must be safe
            if '/' in doc_filename or '\\' in doc_filename:
                 # Although validate_repo_relative_path handles it, canonical_docs should ideally be simple filenames.
                 # We validate the combined path anyway.
                 pass

            filepath = os.path.join(base_path, doc_filename)

            # Normalize to POSIX for consistent ID mapping and graph checks
            filepath = filepath.replace('\\', '/')

            # Validate full path safety
            try:
                filepath = validate_repo_relative_path(filepath)
            except ValueError as e:
                errors.append(f"Invalid document path '{filepath}': {e}")
                continue

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
                # Without ID, we can't reliably add to graph, so skip graph for this file
                continue
            else:
                if doc_id in seen_ids:
                    errors.append(f"Duplicate ID '{doc_id}': {filepath} and {seen_ids[doc_id]}")
                    continue # Skip adding duplicate to graph to avoid confusion
                else:
                    seen_ids[doc_id] = filepath
                    docs_by_id[doc_id] = filepath

            # Add to filename map
            if doc_filename not in docs_by_filename:
                docs_by_filename[doc_filename] = []
            docs_by_filename[doc_filename].append(filepath)

            # 4. Check status
            status = fm.get('status')
            if not status:
                 errors.append(f"Missing 'status' in frontmatter: {filepath}")
            elif status not in ALLOWED_STATUS:
                 errors.append(f"Invalid status '{status}' in frontmatter: {filepath} (Allowed: {ALLOWED_STATUS})")

            # Check canonicality
            canonicality = fm.get('canonicality')
            if not canonicality:
                 errors.append(f"Missing 'canonicality' in frontmatter: {filepath}")
            elif canonicality not in ALLOWED_CANONICALITY:
                 errors.append(f"Invalid canonicality '{canonicality}' in frontmatter: {filepath} (Allowed: {ALLOWED_CANONICALITY})")

            # Check doc_type
            doc_type = fm.get('doc_type')
            if not doc_type:
                 errors.append(f"Missing 'doc_type' in frontmatter: {filepath}")
            elif doc_type not in ALLOWED_DOC_TYPES:
                 errors.append(f"Invalid doc_type '{doc_type}' in frontmatter: {filepath} (Allowed: {ALLOWED_DOC_TYPES})")

            # Check title
            title = fm.get('title')
            if not title:
                 errors.append(f"Missing 'title' in frontmatter: {filepath}")

            # Check summary
            summary = fm.get('summary')
            if not summary:
                 errors.append(f"Missing 'summary' in frontmatter: {filepath}")

            # 5. Check role
            role = fm.get('role')
            if not role:
                 errors.append(f"Missing 'role' in frontmatter: {filepath}")
            elif role not in ALLOWED_ROLES:
                 errors.append(f"Invalid 'role' '{role}': {filepath} (Allowed: {ALLOWED_ROLES})")

            # 5a. Check optional doc_role (only if present)
            doc_role = fm.get('doc_role')
            if doc_role is not None and doc_role not in ALLOWED_DOC_ROLES:
                errors.append(f"Invalid doc_role '{doc_role}' in frontmatter: {filepath} (Allowed: {ALLOWED_DOC_ROLES})")

            # 5b. Check optional reference_policy (only if present)
            reference_policy = fm.get('reference_policy')
            if reference_policy is not None and reference_policy not in ALLOWED_REFERENCE_POLICIES:
                errors.append(f"Invalid reference_policy '{reference_policy}' in frontmatter: {filepath} (Allowed: {ALLOWED_REFERENCE_POLICIES})")

            # 6. Check last_reviewed format
            reviewed = fm.get('last_reviewed')
            if not reviewed:
                 errors.append(f"Missing 'last_reviewed' in frontmatter: {filepath}")
            elif not re.match(r'^\d{4}-\d{2}-\d{2}$', str(reviewed)):
                 errors.append(f"Invalid 'last_reviewed' format (expected YYYY-MM-DD): {filepath} ({reviewed})")

            # 7. Check verifies_with
            verifies = fm.get('verifies_with')
            if verifies:
                if isinstance(verifies, str):
                    verifies = [verifies]

                if isinstance(verifies, list):
                    for v_script in verifies:
                        if not os.path.exists(v_script):
                            errors.append(f"Verification script missing: {v_script} (referenced in {filepath})")
                else:
                    errors.append(f"Invalid 'verifies_with' format (expected list or string): {filepath}")

    # Second pass: Dependency Graph Check
    print("Checking dependency graph...")

    # Build graph for cycle detection (Nodes are doc_ids)
    graph = {}

    for doc_id, filepath in docs_by_id.items():
        fm = parse_frontmatter(filepath)
        if not fm:
            continue

        # Recommendation: depends_on should prefer document IDs over filenames; filenames only if unambiguous.
        deps = fm.get('depends_on', [])

        # Normalize deps to list
        if isinstance(deps, str):
            deps = [deps]
        elif deps is None:
            deps = []
        elif not isinstance(deps, list):
            errors.append(f"Invalid 'depends_on' format (expected list or string): {filepath}")
            continue

        current_node = doc_id
        graph[current_node] = []

        for dep in deps:
            # Dependency can be:
            # 1. A doc ID (ideal)
            # 2. A filename (ambiguous if duplicates exist, but we check)
            # 3. A filepath relative to root (ideal)

            target_id = None

            # Case 1: Is it a known ID?
            if dep in docs_by_id:
                target_id = dep

            # Case 2: Is it a filename?
            elif dep in docs_by_filename:
                candidates = docs_by_filename[dep]
                if len(candidates) == 1:
                    # Resolve ID from path
                    # Iterate docs_by_id to find key for this path (inefficient but safe)
                    for d_id, d_path in docs_by_id.items():
                        if d_path == candidates[0]:
                            target_id = d_id
                            break
                else:
                    errors.append(f"Ambiguous dependency '{dep}' in {filepath}: matches multiple files {candidates}. Use a document ID (recommended) or an exact path. Filename matching requires an exact match to the `depends_on` string.")
                    continue

            # Case 3: Is it a filepath?
            else:
                # Try to normalize relative paths (e.g. ../norm/constitution.md)
                doc_dir = os.path.dirname(filepath)
                norm_dep = normalize_path(doc_dir, dep)

                if os.path.exists(norm_dep):
                    # Check if this normalized path maps to a known doc ID
                    for d_id, d_path in docs_by_id.items():
                        if d_path == norm_dep:
                            target_id = d_id
                            break

                    if not target_id:
                        # Existing file but not a canonical doc (e.g. script, external check)
                        pass
                elif os.path.exists(dep):
                    # Fallback for paths that worked without normalization (already relative to root?)
                    for d_id, d_path in docs_by_id.items():
                        if d_path == dep:
                            target_id = d_id
                            break
                else:
                    errors.append(f"Dependency not found: '{dep}' (checked as '{norm_dep}') in {filepath}. Use a document ID (recommended) or an exact path. Filename matching requires an exact match to the `depends_on` string.")
                    continue

            if target_id:
                graph[current_node].append(target_id)

    # Cycle Detection
    visited = set()
    rec_stack = set()

    def has_cycle(node):
        visited.add(node)
        rec_stack.add(node)

        for neighbor in graph.get(node, []):
            if neighbor not in visited:
                if has_cycle(neighbor):
                    return True
            elif neighbor in rec_stack:
                return True

        rec_stack.remove(node)
        return False

    # Check for cycles in all components
    for node in graph:
        if node not in visited:
            if has_cycle(node):
                errors.append(f"Dependency cycle detected involving document ID: {node}")

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
