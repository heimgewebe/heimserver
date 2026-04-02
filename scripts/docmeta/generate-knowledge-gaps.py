#!/usr/bin/env python3
import os
import sys

sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from scripts.lib.docmeta import load_repo_index, parse_frontmatter, parse_impl_registry, MANIFEST_PATH

def _resolve_reference_policy(doc_role, reference_policy_raw):
    """Derive the effective reference policy for a document.

    Explicit reference_policy in frontmatter always wins.
    Without an explicit value the policy defaults to 'optional' for all
    doc_roles.  Only a deliberate reference_policy: required causes an
    unreferenced document to appear as an Epistemic Gap (Action Required).
    """
    if reference_policy_raw in ('required', 'optional', 'none'):
        return reference_policy_raw
    # Without an explicit reference_policy, all doc_roles default to 'optional'.
    # Only an explicit reference_policy: required in frontmatter triggers the
    # "Action Required" level — inferring hard gaps from missing depends_on
    # links alone over-extends the semantics of that dependency field.
    return 'optional'

def generate_knowledge_gaps():
    implementations = parse_impl_registry()

    gaps = {
        "operational_gaps": [],
        "terminology_gaps": [],
        "epistemic_gaps": [],
        "review_signals": [],
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
                        'basename': os.path.basename(filepath),
                        'canonicality': fm.get('canonicality'),
                        'depends_on': fm.get('depends_on', []),
                        'doc_role': fm.get('doc_role', 'leaf'),
                        'reference_policy': fm.get('reference_policy', ''),
                    }

        for doc_id, meta in all_docs.items():
            canonicality = meta['canonicality']
            deps = meta['depends_on']
            effective_policy = _resolve_reference_policy(
                meta['doc_role'], meta['reference_policy']
            )

            # Canonical document: check incoming references
            if canonicality == 'canonical':
                is_referenced = False
                for other_doc_id, other_meta in all_docs.items():
                    if other_doc_id != doc_id:
                        other_deps = other_meta['depends_on']
                        if isinstance(other_deps, str):
                            other_deps = {other_deps}
                        else:
                            other_deps = set(other_deps)
                        # Match by doc_id, full filepath, or basename
                        if (doc_id in other_deps
                                or meta['filepath'] in other_deps
                                or meta['basename'] in other_deps):
                            is_referenced = True
                            break

                if not is_referenced and effective_policy != 'none':
                    msg = (
                        f"`{doc_id}` (`{meta['filepath']}`) "
                        f"has no detected incoming references."
                    )
                    if effective_policy == 'required':
                        gaps["epistemic_gaps"].append(
                            f"Unreferenced canonical document: {msg}"
                        )
                    else:  # optional
                        # Explain why this is only a signal, not a gap
                        if meta['reference_policy'] in ('optional', 'none'):
                            reason = f"reference_policy={meta['reference_policy']} (explicitly set)"
                        else:
                            reason = f"doc_role={meta['doc_role']} (default policy: optional)"
                        gaps["review_signals"].append(
                            f"Reference review signal: {msg} ({reason})"
                        )

            # Derived document: must declare its source
            elif canonicality == 'derived':
                if not deps:
                    gaps["epistemic_gaps"].append(
                        f"Source Traceability Gap: `{doc_id}` (`{meta['filepath']}`) "
                        f"is marked as derived but does not reference a canonical source via `depends_on`."
                    )

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

        f.write("\n## Epistemic Gaps (Action Required)\n")
        if gaps["epistemic_gaps"]:
            for gap in gaps["epistemic_gaps"]:
                f.write(f"- {gap}\n")
        else:
            f.write("_No actionable epistemic gaps detected._\n")

        f.write("\n## Reference Review Signals (Contextual)\n")
        if gaps["review_signals"]:
            for signal in gaps["review_signals"]:
                f.write(f"- {signal}\n")
        else:
            f.write("_No reference review signals._\n")

    print("Successfully generated docs/_generated/knowledge-gaps.md")

if __name__ == '__main__':
    generate_knowledge_gaps()
