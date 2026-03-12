#!/usr/bin/env python3
import os
import sys

sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from scripts.lib.docmeta import load_repo_index, MANIFEST_PATH

def get_discovery_roots():
    roots = []
    if os.path.exists('repo.meta.yaml'):
        with open('repo.meta.yaml', 'r', encoding='utf-8') as f:
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

def generate_architecture_drift():
    manifest = load_repo_index(MANIFEST_PATH) if os.path.exists(MANIFEST_PATH) else {}
    zones = manifest.get('zones', {})

    documented_zones = [zone.get('path', '').rstrip('/') for zone in zones.values()]
    discovery_roots = get_discovery_roots()

    # Simple heuristic: scan top level directories
    all_top_level = [d for d in os.listdir('.') if os.path.isdir(d) and not d.startswith('.') and d not in ['docs', 'audit', 'scripts', 'manifest']]

    undocumented_paths = []
    for d in all_top_level:
        if d not in documented_zones and d not in discovery_roots:
            undocumented_paths.append(d)

    os.makedirs('docs/_generated', exist_ok=True)
    with open('docs/_generated/architecture-drift.md', 'w', encoding='utf-8') as f:
        f.write("# Architecture Drift Report\n\n")
        f.write("Generated automatically by `scripts/docmeta/generate-architecture-drift.py`. Do not edit.\n\n")

        f.write("## Structural Drift Summary\n")
        if undocumented_paths:
            f.write("**Severity:** `warn`\n\n")
            f.write("The following top-level paths exist but are not tracked as canonical zones or discovery roots:\n")
            for p in sorted(undocumented_paths):
                f.write(f"- `{p}/`\n")
        else:
            f.write("**Severity:** `info`\n\n")
            f.write("All major top-level paths appear to be tracked in `manifest/repo-index.yaml` or `repo.meta.yaml`.\n")

    print("Successfully generated docs/_generated/architecture-drift.md")

if __name__ == '__main__':
    generate_architecture_drift()
