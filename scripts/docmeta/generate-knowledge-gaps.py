#!/usr/bin/env python3
import os

# Re-use parser
def parse_impl_registry():
    impl_registry_path = 'audit/impl-registry.yaml'
    implementations = []
    if os.path.exists(impl_registry_path):
        try:
            with open(impl_registry_path, 'r', encoding='utf-8') as f:
                content = f.read()

            current_impl = {}
            in_documented_by = False

            for line in content.splitlines():
                stripped = line.strip()
                if stripped.startswith('- id:'):
                    if current_impl:
                        implementations.append(current_impl)
                    current_impl = {'id': stripped.split(':', 1)[1].strip(), 'documented_by': []}
                    in_documented_by = False
                elif stripped.startswith('path:'):
                    current_impl['path'] = stripped.split(':', 1)[1].strip()
                    in_documented_by = False
                elif stripped.startswith('impl_type:'):
                    current_impl['impl_type'] = stripped.split(':', 1)[1].strip()
                    in_documented_by = False
                elif stripped.startswith('documented_by:'):
                    in_documented_by = True
                elif in_documented_by and stripped.startswith('- '):
                    current_impl['documented_by'].append(stripped[2:].strip())
                elif stripped and not stripped.startswith('- '):
                    in_documented_by = False

            if current_impl:
                implementations.append(current_impl)
        except Exception as e:
            pass
    return implementations

def generate_knowledge_gaps():
    implementations = parse_impl_registry()

    gaps = {
        "operational_gaps": [],
        "terminology_gaps": []
    }

    for impl in implementations:
        docs = impl.get('documented_by', [])
        if not docs:
            gaps["operational_gaps"].append(f"Critical implementation `{impl.get('id')}` (`{impl.get('path')}`) has no documentation linkage.")

    # Extremely basic heuristic: if glossary exists, it's a good start. We aren't doing full NLP here yet.
    if not os.path.exists('architecture/glossary.md'):
         gaps["terminology_gaps"].append("No canonical `architecture/glossary.md` found to govern terms.")

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

    print("Successfully generated docs/_generated/knowledge-gaps.md")

if __name__ == '__main__':
    generate_knowledge_gaps()
