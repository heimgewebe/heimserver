#!/usr/bin/env python3
import os
import sys
import re
import shlex

sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from scripts.lib.docmeta import load_repo_index, get_discovery_roots, parse_impl_registry, MANIFEST_PATH


def extract_makefile_scripts():
    scripts = set()
    if os.path.exists('Makefile'):
        with open('Makefile', 'r', encoding='utf-8') as f:
            for line in f:
                normalized = re.sub(r'[;&|()]', ' ', line.strip())
                if not normalized or normalized.startswith('#'):
                    continue

                try:
                    tokens = shlex.split(normalized)
                except ValueError:
                    continue

                for index, token in enumerate(tokens):
                    command = token.lstrip('@-')
                    if command not in ('bash', 'python3'):
                        continue

                    cursor = index + 1
                    while cursor < len(tokens):
                        candidate = tokens[cursor]

                        if candidate == '-m':
                            cursor += 2
                            continue

                        if candidate.startswith('-'):
                            cursor += 1
                            continue

                        if candidate.endswith(('.sh', '.py')):
                            scripts.add(candidate)

                        cursor += 1
    return scripts

def get_all_ci_scripts():
    scripts = set()
    ci_dir = 'scripts/ci'
    if os.path.exists(ci_dir) and os.path.isdir(ci_dir):
        for filename in os.listdir(ci_dir):
            if filename.endswith('.py') or filename.endswith('.sh'):
                scripts.add(os.path.join(ci_dir, filename).replace('\\', '/'))
    return scripts

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

    # Implicit Infrastructure Coupling
    registered_impls = parse_impl_registry()
    registered_paths = {impl.get('path') for impl in registered_impls if impl.get('path')}

    makefile_scripts = extract_makefile_scripts()
    ci_scripts = get_all_ci_scripts()

    all_discovered_scripts = makefile_scripts.union(ci_scripts)
    unregistered_scripts = sorted(list(all_discovered_scripts - registered_paths))

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

        f.write("\n## Implicit Dependencies (Infrastructure Coupling)\n")
        if unregistered_scripts:
            f.write("**Severity:** `warn`\n\n")
            f.write("The following scripts were discovered via `Makefile` references or by scanning the `scripts/ci/` directory but are not registered in `audit/impl-registry.yaml`:\n")
            for script in unregistered_scripts:
                f.write(f"- `{script}`\n")
            f.write("\n_Recommendation: Register these scripts to ensure they are formally tracked and documented._\n")
        else:
            f.write("**Severity:** `info`\n\n")
            f.write("No implicit infrastructure scripts detected. All discovered scripts are registered.\n")

    print("Successfully generated docs/_generated/architecture-drift.md")

if __name__ == '__main__':
    generate_architecture_drift()
