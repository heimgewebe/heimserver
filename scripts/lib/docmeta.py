# scripts/lib/docmeta.py

import os
import re
import sys

MANIFEST_PATH = 'manifest/repo-index.yaml'
IMPL_REGISTRY_PATH = 'audit/impl-registry.yaml'
ALLOWED_ROLES = {"norm", "reality", "action", "runbooks", "docs", "decisions"}
ALLOWED_STATUS = {"active", "deprecated", "experimental", "archived"}
ALLOWED_CANONICALITY = {"canonical", "derived", "explanatory"}
ALLOWED_DOC_TYPES = {"identity", "architecture", "decision", "runbook", "guide", "reference", "policy", "status", "generated", "archive", "experimental"}
# Optional doc_role field: controls reference-expectation semantics.
#   entry  → top-level hub, not expected to have incoming references (default policy: optional)
#   leaf   → content document that should be referenced from elsewhere (default policy: required)
#   bridge → connector document linking two conceptual areas (default policy: required)
ALLOWED_DOC_ROLES = {"entry", "leaf", "bridge"}
# Optional reference_policy field: explicit override for the reference check.
#   required → unreferenced status is reported as a Gap (action required)
#   optional → unreferenced status is reported as a Review Signal (contextual)
#   none     → reference check suppressed entirely
ALLOWED_REFERENCE_POLICIES = {"required", "optional", "none"}

def _unquote(val):
    """Removes surrounding quotes from a string."""
    val = val.strip()
    if (val.startswith('"') and val.endswith('"')) or (val.startswith("'") and val.endswith("'")):
        return val[1:-1]
    return val

def load_repo_index(path=MANIFEST_PATH):
    """Parses manifest/repo-index.yaml manually."""
    data = {'zones': {}, 'checks': []}
    current_zone = None
    in_checks = False

    if not os.path.exists(path):
        raise FileNotFoundError(f"Manifest not found at {path}")

    with open(path, 'r', encoding='utf-8') as f:
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
                # In zones
                if line.startswith('  ') and not line.startswith('    ') and stripped.endswith(':'):
                    zone_name = stripped[:-1]
                    current_zone = zone_name
                    data['zones'][current_zone] = {'path': '', 'canonical_docs': []}

                elif line.startswith('    path:'):
                    path_val = stripped.split(':', 1)[1].strip()
                    if current_zone:
                        data['zones'][current_zone]['path'] = path_val

                elif line.startswith('    canonical_docs:'):
                    pass

                elif line.startswith('      - '):
                    doc = stripped[2:]
                    if current_zone:
                        data['zones'][current_zone]['canonical_docs'].append(doc)
    return data

def normalize_path(base_dir, rel_path):
    """Resolves a relative path from base_dir to a repo-relative path (POSIX)."""
    # If it's already absolute (starts with /), treat it as repo-relative
    if rel_path.startswith('/'):
        return rel_path.lstrip('/')

    # Resolve relative path
    full_path = os.path.normpath(os.path.join(base_dir, rel_path))

    # Ensure forward slashes for POSIX consistency
    return full_path.replace('\\', '/')

def validate_repo_relative_path(path):
    """
    Validates that a path is relative to the repo root and does not traverse upwards.
    Returns the normalized path if valid, raises ValueError if invalid.
    """
    # Normalize to POSIX
    normalized = path.replace('\\', '/')

    # Check for absolute path (including Windows drive letters)
    if os.path.isabs(normalized) or (os.name == 'nt' and ':' in normalized):
        raise ValueError(f"Path must be relative to repo root, got absolute path: {path}")

    # Normalize using os.path.normpath to resolve .. and .
    # Note: On Windows this uses backslashes, so we convert back
    resolved = os.path.normpath(normalized).replace('\\', '/')

    # Check for upward traversal
    if resolved.startswith('../') or resolved == '..' or '/../' in resolved:
        raise ValueError(f"Path traverses outside repo root: {path}")

    return resolved

def parse_frontmatter(filepath):
    """Parses Markdown frontmatter manually."""
    if not os.path.exists(filepath):
        return None

    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # CRLF-tolerant regex
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

        # Check if line is a list item
        if stripped.startswith('- '):
            if current_list_key:
                val = _unquote(stripped[2:])
                data[current_list_key].append(val)
            continue

        if ':' in stripped:
            key, val = stripped.split(':', 1)
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
                    clean_items = [_unquote(item) for item in items]
                    data[key] = clean_items
                current_list_key = None
            else:
                # Plain value
                data[key] = _unquote(val)
                current_list_key = None

    return data

def get_discovery_roots(meta_path='repo.meta.yaml'):
    """Parses discovery_roots from repo.meta.yaml (line-based)."""
    roots = []
    if os.path.exists(meta_path):
        with open(meta_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        in_roots = False
        for line in lines:
            if line.startswith('discovery_roots:'):
                in_roots = True
                continue
            if in_roots and line.startswith('  - '):
                roots.append(line.strip()[2:].strip().rstrip('/'))
            elif in_roots and line.strip() and not line.startswith(' '):
                in_roots = False
    return roots

def parse_impl_registry(registry_path=IMPL_REGISTRY_PATH):
    """Parses audit/impl-registry.yaml manually. Returns list of implementation dicts."""
    implementations = []
    if not os.path.exists(registry_path):
        return implementations

    # List fields that are parsed the same way as documented_by
    _list_fields = {'documented_by', 'verified_by', 'supersedes', 'deprecated_by'}

    try:
        with open(registry_path, 'r', encoding='utf-8') as f:
            content = f.read()

        current_impl = {}
        current_list_field = None

        for line in content.splitlines():
            stripped = line.strip()
            if stripped.startswith('- id:'):
                if current_impl:
                    implementations.append(current_impl)
                current_impl = {
                    'id': stripped.split(':', 1)[1].strip(),
                    'documented_by': [],
                    'verified_by': [],
                    'supersedes': [],
                    'deprecated_by': [],
                }
                current_list_field = None
            elif stripped.startswith('path:'):
                current_impl['path'] = stripped.split(':', 1)[1].strip()
                current_list_field = None
            elif stripped.startswith('impl_type:'):
                current_impl['impl_type'] = stripped.split(':', 1)[1].strip()
                current_list_field = None
            elif stripped.startswith('status:'):
                current_impl['status'] = stripped.split(':', 1)[1].strip()
                current_list_field = None
            else:
                # Check for any list-field header (e.g. "documented_by:", "verified_by:")
                matched_list = False
                for field in _list_fields:
                    if stripped.startswith(f'{field}:'):
                        current_list_field = field
                        matched_list = True
                        break

                if not matched_list:
                    if current_list_field and stripped.startswith('- '):
                        current_impl[current_list_field].append(stripped[2:].strip())
                    elif stripped and not stripped.startswith('- '):
                        current_list_field = None

        if current_impl:
            implementations.append(current_impl)
    except Exception as e:
        print(f"Warning: Could not parse impl-registry.yaml: {e}", file=sys.stderr)

    return implementations
