#!/usr/bin/env python3
import os
import sys

sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from scripts.lib.docmeta import load_repo_index, parse_frontmatter, parse_impl_registry, MANIFEST_PATH

def generate_knowledge_gaps():
    implementations = parse_impl_registry()

    gaps = {
        "operational_gaps": [],
        "terminology_gaps": [],
        "epistemic_gaps": []
    }

    for impl in implementations:
        docs = impl.get('documented_by', [])
        if not docs:
            gaps["operational_gaps"].append(f"Critical implementation `{impl.get('id')}` (`{impl.get('path')}`) has no documentation linkage.")

    if not os.path.exists('architecture/glossary.md'):
         gaps["terminology_gaps"].append("No canonical `architecture/glossary.md` found to govern terms.")

    # Canonical Drift Analysis
    if os.path.exists(MANIFEST_PATH):
        manifest = load_repo_index(MANIFEST_PATH)
        zones = manifest.get('zones', {})

        all_docs = {}
        for zone_name, zone_data in zones.items():
            base_path = zone_data.get('path', '')
            for doc in zone_data.get('canonical_docs', []):
                filepath = os.path.join(base_path, doc).replace('\\', '/')
                fm = parse_frontmatter(filepath)
                if fm and 'id' in fm:
                    all_docs[fm['id']] = {
                        'filepath': filepath,
                        'canonicality': fm.get('canonicality'),
                        'depends_on': fm.get('depends_on', [])
                    }

        # Find orphans (nobody depends on them) and missing sources
        for doc_id, meta in all_docs.items():
            canonicality = meta['canonicality']
            deps = meta['depends_on']

            # Orphaned canonical document
            if canonicality == 'canonical':
                is_referenced = False
                for other_doc_id, other_meta in all_docs.items():
                    if other_doc_id != doc_id:
                        other_deps = other_meta['depends_on']
                        if isinstance(other_deps, str):
                            other_deps = [other_deps]

                        # Match by doc_id or filepath
                        if doc_id in other_deps or meta['filepath'] in other_deps or os.path.basename(meta['filepath']) in other_deps:
                            is_referenced = True
                            break

                is_entry_doc = (
                    doc_id.endswith('.index') or
                    'index' in os.path.basename(meta['filepath']).lower() or
                    'runbooks/' in meta['filepath'] or
                    'decisions/' in meta['filepath']
                )

                if not is_referenced and not is_entry_doc:
                    gaps["epistemic_gaps"].append(f"Reference Review Signal: canonical document `{doc_id}` (`{meta['filepath']}`) currently has no detected incoming references. This may still be intentional for certain standalone or operational documents.")

            # Derived document missing source
            elif canonicality == 'derived':
                if not deps or len(deps) == 0:
                    gaps["epistemic_gaps"].append(f"Source Traceability Gap: `{doc_id}` (`{meta['filepath']}`) is marked as derived but does not reference a canonical source via `depends_on`.")

    os.makedirs('docs/_generated', exist_ok=True)
    with open('docs/_generated/knowledge-gaps.md', 'w', encoding='utf-8') as f:
        f.write("# Knowledge Gaps Report\n\n")
        f.write("Generated automatically by `scripts/docmeta/generate-knowledge-gaps.py`. Do not edit.\n\n")

        f.write("## Operational Gaps\n")
        if gaps["operational_gaps"]:
            for gap in gaps["operational_gaps"]:
                f.write(f"- {gap}\n")
        else:
            f.write("_No explicit operational knowledge gaps detected._\n")

        f.write("\n## Terminology Gaps\n")
        if gaps["terminology_gaps"]:
            for gap in gaps["terminology_gaps"]:
                f.write(f"- {gap}\n")
        else:
            f.write("_No major terminology gaps detected (Glossary is present)._\n")

        f.write("\n## Reference Review Signals\n")
        if gaps["epistemic_gaps"]:
            for gap in gaps["epistemic_gaps"]:
                f.write(f"- {gap}\n")
        else:
            f.write("_No semantic inflation or canonical drift detected._\n")

    print("Successfully generated docs/_generated/knowledge-gaps.md")

if __name__ == '__main__':
    generate_knowledge_gaps()
