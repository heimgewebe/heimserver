#!/usr/bin/env python3
import os
import sys

sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from scripts.lib.docmeta import load_repo_index, parse_impl_registry, MANIFEST_PATH

def generate_doc_coverage():
    implementations = parse_impl_registry()
    manifest = load_repo_index(MANIFEST_PATH) if os.path.exists(MANIFEST_PATH) else {}
    zones = manifest.get('zones', {})

    # Build list of all valid canonical document paths
    canonical_doc_paths = set()
    for zone_name, zone_data in zones.items():
        base_path = zone_data.get('path', '')
        for doc in zone_data.get('canonical_docs', []):
            filepath = os.path.join(base_path, doc).replace('\\', '/')
            canonical_doc_paths.add(filepath)

    os.makedirs('docs/_generated', exist_ok=True)
    with open('docs/_generated/doc-coverage.md', 'w', encoding='utf-8') as f:
        f.write("# Documentation Coverage Report\n\n")
        f.write("Generated automatically by `scripts/docmeta/generate-doc-coverage.py`. Do not edit.\n\n")

        f.write("| Implementation | Type | Documented By | Coverage Status |\n")
        f.write("|---|---|---|---|\n")

        for impl in implementations:
            docs = impl.get('documented_by', [])
            impl_id = impl.get('id', 'unknown')
            impl_type = impl.get('impl_type', 'unknown')

            if not docs:
                status = "⚠ Undocumented"
                docs_str = "-"
            else:
                invalid_docs = []
                valid_docs = []
                for doc in docs:
                    # Check existence
                    if not os.path.exists(doc):
                        invalid_docs.append(f"{doc} (Missing File)")
                    elif doc.replace('\\', '/') not in canonical_doc_paths:
                        invalid_docs.append(f"{doc} (Not Canonical / Not Registered)")
                    else:
                        valid_docs.append(doc)

                if invalid_docs:
                    status = "❌ Invalid Coverage"
                    docs_str = ", ".join([f"`{d}`" for d in valid_docs] + [f"`{d}`" for d in invalid_docs])
                else:
                    status = "✅ Fully Documented"
                    docs_str = ", ".join([f"`{d}`" for d in valid_docs])

            f.write(f"| `{impl_id}` | {impl_type} | {docs_str} | {status} |\n")

    print("Successfully generated docs/_generated/doc-coverage.md")

if __name__ == '__main__':
    generate_doc_coverage()
