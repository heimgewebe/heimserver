# scripts/lib/docmeta.py

import os
import re

MANIFEST_PATH = 'manifest/repo-index.yaml'
ALLOWED_ROLES = {"norm", "reality", "action", "runbooks", "docs", "decisions"}
ALLOWED_STATUS = {"active", "deprecated", "experimental", "archived"}
ALLOWED_CANONICALITY = {"canonical", "derived", "explanatory"}
ALLOWED_DOC_TYPES = {"identity", "architecture", "decision", "runbook", "guide", "reference", "policy", "status", "generated", "archive", "experimental"}

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
