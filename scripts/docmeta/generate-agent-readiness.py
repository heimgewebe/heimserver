#!/usr/bin/env python3
import os

def evaluate_readiness():
    dimensions = []

    # 1. Canonical Entry Clarity
    if os.path.exists('repo.meta.yaml') and os.path.exists('AGENTS.md') and os.path.exists('docs/index.md'):
        dimensions.append({
            "dimension": "Canonical Entry Clarity",
            "score": 5,
            "reasoning": "Clear entry points defined via repo.meta.yaml, AGENTS.md, and docs/index.md.",
            "next_action": "Maintain."
        })
    else:
        dimensions.append({
            "dimension": "Canonical Entry Clarity",
            "score": 2,
            "reasoning": "Missing foundational entry files.",
            "next_action": "Ensure repo.meta.yaml and AGENTS.md exist."
        })

    # 2. Guarded Path Clarity
    if os.path.exists('agent-policy.yaml'):
        dimensions.append({
            "dimension": "Guarded Path Clarity",
            "score": 5,
            "reasoning": "agent-policy.yaml explicitly defines boundaries.",
            "next_action": "Maintain."
        })
    else:
        dimensions.append({
            "dimension": "Guarded Path Clarity",
            "score": 0,
            "reasoning": "No machine-readable policy found.",
            "next_action": "Create agent-policy.yaml."
        })

    # 3. Drift Visibility
    if os.path.exists('docs/_generated/architecture-drift.md') and os.path.exists('ops/checks/preflight.sh'):
        dimensions.append({
            "dimension": "Drift Visibility",
            "score": 4,
            "reasoning": "Structural drift and operational preflight checks exist.",
            "next_action": "Integrate findings into CI gating."
        })
    else:
        dimensions.append({
            "dimension": "Drift Visibility",
            "score": 1,
            "reasoning": "Weak visibility into system drift.",
            "next_action": "Implement architecture-drift generation."
        })

    return dimensions

def generate_agent_readiness():
    dimensions = evaluate_readiness()

    os.makedirs('docs/_generated', exist_ok=True)
    with open('docs/_generated/agent-readiness.md', 'w', encoding='utf-8') as f:
        f.write("# Agent Readiness Report\n\n")
        f.write("Generated automatically by `scripts/docmeta/generate-agent-readiness.py`. Do not edit.\n\n")

        f.write("| Dimension | Score (0-5) | Reasoning | Recommended Next Action |\n")
        f.write("|---|---|---|---|\n")
        for dim in dimensions:
            f.write(f"| {dim['dimension']} | {dim['score']} | {dim['reasoning']} | {dim['next_action']} |\n")

    print("Successfully generated docs/_generated/agent-readiness.md")

if __name__ == '__main__':
    generate_agent_readiness()
