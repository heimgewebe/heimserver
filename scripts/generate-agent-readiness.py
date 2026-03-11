#!/usr/bin/env python3
import os
import sys
import json

def check_file_exists(path):
    return os.path.exists(path)

def generate_agent_readiness():
    score = 0
    total = 0

    checks = {
        "Kanonische Repo-Identität (repo.meta.yaml)": "repo.meta.yaml",
        "Handlungsgrenzen für Agents (agent-policy.yaml)": "agent-policy.yaml",
        "Terminologie-/Glossar-Governance (architecture/glossary.md)": "architecture/glossary.md",
        "Semantische Relationen (docs/_generated/relations.json)": "docs/_generated/relations.json",
        "Generierte Orientierung (SYSTEM_MAP.md)": "SYSTEM_MAP.md",
        "Wahrheitsschichten (manifest/repo-index.yaml)": "manifest/repo-index.yaml",
        "Agent Einstiegspunkt (AGENTS.md)": "AGENTS.md",
        "Verifikationspfade (ops/checks/preflight.sh)": "ops/checks/preflight.sh",
        "Implementierungs-Registry (audit/impl-registry.yaml)": "audit/impl-registry.yaml",
        "Kritische Implementierungen Übersicht (docs/_generated/impl-index.md)": "docs/_generated/impl-index.md",
        "Historisierungskarte (docs/_generated/supersession-map.md)": "docs/_generated/supersession-map.md",
        "Dokumentations-Einstieg (docs/index.md)": "docs/index.md",
        "Automatischer Dokumenten-Index (docs/_generated/doc-index.md)": "docs/_generated/doc-index.md",
        "Entscheidungs-Historie (docs/decisions/)": "docs/decisions/"
    }

    results = {}

    for label, path in checks.items():
        total += 1
        exists = check_file_exists(path)
        if exists:
            score += 1
        results[label] = {
            "path": path,
            "status": "pass" if exists else "fail"
        }

    readiness_percentage = (score / total) * 100 if total > 0 else 0

    report_json = {
        "score": score,
        "total": total,
        "percentage": readiness_percentage,
        "checks": results
    }

    os.makedirs('docs/_generated', exist_ok=True)
    with open('docs/_generated/agent-readiness.json', 'w', encoding='utf-8') as f:
        json.dump(report_json, f, indent=2)

    with open('docs/_generated/agent-readiness.md', 'w', encoding='utf-8') as f:
        f.write("# Agent Readiness Report\n\n")
        f.write(f"**Score:** {score}/{total} ({readiness_percentage:.1f}%)\n\n")
        f.write("## Checks\n\n")
        f.write("| Status | Check | Path |\n")
        f.write("|---|---|---|\n")
        for label, data in results.items():
            icon = "✅" if data["status"] == "pass" else "❌"
            f.write(f"| {icon} | {label} | `{data['path']}` |\n")

    print("Successfully generated docs/_generated/agent-readiness.json")
    print("Successfully generated docs/_generated/agent-readiness.md")

if __name__ == '__main__':
    generate_agent_readiness()
