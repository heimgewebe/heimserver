#!/usr/bin/env python3
import os

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
                elif stripped.startswith('status:'):
                    current_impl['status'] = stripped.split(':', 1)[1].strip()
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
            print(f"Warning: Could not parse impl-registry.yaml: {e}")
    return implementations

def generate_doc_coverage():
    implementations = parse_impl_registry()

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
                # Basic heuristic: if it has docs, it's considered covered for now.
                status = "✅ Fully Documented"
                docs_str = ", ".join([f"`{d}`" for d in docs])

            f.write(f"| `{impl_id}` | {impl_type} | {docs_str} | {status} |\n")

    print("Successfully generated docs/_generated/doc-coverage.md")

if __name__ == '__main__':
    generate_doc_coverage()
