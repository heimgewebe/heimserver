#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts.lib.docmeta import load_repo_index, parse_frontmatter

ACTIVE_REPOSITORY_DOCUMENTS = {
    "architecture/docmeta.schema.md",
    "architecture/glossary.md",
    "runbooks/adding-docs.md",
}
HISTORICAL_ZONES = {"norm", "reality", "action", "runbooks"}
BANNER = "Historische Referenz — nicht ausführen."
FORBIDDEN_STANDARD_CHECK = "ops/checks/preflight.sh"
STATIC_CHECK = "scripts/ci/check_retired_reference_contract.py"
HISTORICAL_METADATA_PREFIXES = (
    "Historical ",
    "Historische ",
    "Historischer ",
    "Historisches ",
    "Supersedierte ",
)
FORBIDDEN_CURRENT_MARKERS = (
    "Status: Operativ kanonisch",
    "⛔️ OPERATIVES DOKUMENT · KANONISCH",
    "⛔️ OPERATIONAL RUNBOOK",
    "## Rolle (kanonisch)",
    "Scope: Kanonische Wahrheit",
    "Kanonische Namens- und Adressierungsarchitektur",
    "Dieses Dokument ist die kanonische operative Quelle",
    "Änderungen an diesem Runbook gelten als führend.",
    "## Kanonischer Secrets-Pfad",
    "dürfen keine eigenständigen operativen Details",
    "müssen auf dieses Runbook verweisen",
    "Zur Verifikation der Gateway-Konfiguration (auszuführen",
    "Die Konfiguration muss mit",
)
HOST_READ_SCRIPTS = (
    "ops/checks/preflight.sh",
    "ops/checks/snapshot.sh",
)
BLOCKED_MUTATION_SCRIPT = "ops/init-secrets-path.sh"


def _read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def _section(text: str, start: str, end: str) -> str:
    return text.split(start, 1)[-1].split(end, 1)[0]


def main() -> int:
    errors: list[str] = []
    checked = 0

    manifest = load_repo_index(str(ROOT / "manifest/repo-index.yaml"))
    indexed_documents: set[str] = set()
    discovered_documents: set[str] = set()

    for zone_name, zone in manifest.get("zones", {}).items():
        if zone_name not in HISTORICAL_ZONES:
            continue
        base = Path(zone.get("path", ""))
        indexed_documents.update((base / document).as_posix() for document in zone.get("canonical_docs", []))
        zone_root = ROOT / base
        if not zone_root.is_dir():
            errors.append(f"manifest/repo-index.yaml: historical zone path missing: {base}")
            continue
        discovered_documents.update(path.relative_to(ROOT).as_posix() for path in zone_root.rglob("*.md"))

    historical_documents = discovered_documents - ACTIVE_REPOSITORY_DOCUMENTS
    for path in sorted(historical_documents):
        if path not in indexed_documents:
            errors.append(f"{path}: historical document is not indexed")
        full_path = ROOT / path
        frontmatter = parse_frontmatter(str(full_path))
        if frontmatter is None:
            errors.append(f"{path}: missing frontmatter")
            continue
        checked += 1
        if frontmatter.get("status") not in {"deprecated", "archived"}:
            errors.append(f"{path}: status must be deprecated or archived")
        if frontmatter.get("canonicality") != "explanatory":
            errors.append(f"{path}: canonicality must be explanatory")
        for field in ("title", "summary"):
            value = str(frontmatter.get(field, ""))
            if not value.startswith(HISTORICAL_METADATA_PREFIXES):
                errors.append(f"{path}: {field} is not explicitly historical: {value}")
        verifies = frontmatter.get("verifies_with") or []
        if verifies:
            errors.append(f"{path}: historical document retains active verifier bindings: {verifies}")
        document_text = full_path.read_text(encoding="utf-8")
        if BANNER not in document_text:
            errors.append(f"{path}: historical non-execution banner missing")
        for marker in FORBIDDEN_CURRENT_MARKERS:
            if marker in document_text:
                errors.append(f"{path}: current-authority marker remains: {marker}")

    for path in sorted(indexed_documents - ACTIVE_REPOSITORY_DOCUMENTS - discovered_documents):
        errors.append(f"{path}: indexed historical document is missing")

    checks = manifest.get("checks", [])
    if FORBIDDEN_STANDARD_CHECK in checks:
        errors.append("manifest/repo-index.yaml: preflight remains a standard check")
    if STATIC_CHECK not in checks:
        errors.append("manifest/repo-index.yaml: retirement contract check missing")

    for path, section_name in (
        ("repo.meta.yaml", "required_checks"),
        ("agent-policy.yaml", "required_checks_before_patch"),
    ):
        text = _read(path)
        if f"  - bash {FORBIDDEN_STANDARD_CHECK}" in text or f"  - {FORBIDDEN_STANDARD_CHECK}" in text:
            errors.append(f"{path}: preflight remains in {section_name}")
        if STATIC_CHECK not in text:
            errors.append(f"{path}: retirement contract check missing")

    agents = _read("AGENTS.md")
    required_section = _section(agents, "## Erforderliche Checks", "## Häufige Fallen")
    if FORBIDDEN_STANDARD_CHECK in required_section:
        errors.append("AGENTS.md: preflight remains a required check")
    if STATIC_CHECK not in required_section:
        errors.append("AGENTS.md: retirement contract check missing")

    repo_meta = _read("repo.meta.yaml")
    if "status: retired-reference" not in repo_meta:
        errors.append("repo.meta.yaml: retired-reference status missing")
    canonical_section = _section(repo_meta, "canonical_sources:", "historical_reference_sources:")
    for forbidden_source in ("architecture/", "runtime/", "operations/", "runbooks/", FORBIDDEN_STANDARD_CHECK):
        if forbidden_source in canonical_section:
            errors.append(f"repo.meta.yaml: historical source remains canonical: {forbidden_source}")
    if "historical_reference_sources:" not in repo_meta:
        errors.append("repo.meta.yaml: historical_reference_sources missing")
    for section_name in ("safe_read_paths", "guarded_write_paths"):
        section = repo_meta.split(f"{section_name}:", 1)[-1].split("\n\n", 1)[0]
        for required_path in ("architecture/", "runtime/"):
            if f"  - {required_path}" not in section:
                errors.append(f"repo.meta.yaml: {required_path} missing from {section_name}")

    makefile = _read("Makefile")
    preflight_section = _section(makefile, "preflight:", "\nsnapshot:")
    snapshot_section = _section(makefile, "snapshot:", "\nredact:")
    secrets_section = _section(makefile, "secrets:", "\nvalidate-retired-reference:")
    for target, section in (("preflight", preflight_section), ("snapshot", snapshot_section)):
        if "ALLOW_HISTORICAL_HOST_READ" not in section:
            errors.append(f"Makefile: {target} lacks explicit historical host-read guard")
    if "sudo" in secrets_section or "Blocked: Heimserver is retired" not in secrets_section:
        errors.append("Makefile: secrets target is not fail-closed for retired state")

    justfile = _read("justfile")
    for forbidden in (*HOST_READ_SCRIPTS, BLOCKED_MUTATION_SCRIPT, "sudo"):
        if forbidden in justfile:
            errors.append(f"justfile: bypasses guarded Make targets through {forbidden}")
    for target in ("preflight", "snapshot", "secrets"):
        if f"{target}:\n  make {target}" not in justfile:
            errors.append(f"justfile: {target} does not delegate to guarded Make target")

    for script in HOST_READ_SCRIPTS:
        script_text = _read(script)
        guard_index = script_text.find("ALLOW_HISTORICAL_HOST_READ")
        first_host_operation = min(
            (index for token in ("ss ", "date +", "git rev-parse", "mkdir -p") if (index := script_text.find(token)) >= 0),
            default=-1,
        )
        if guard_index < 0 or "exit 2" not in script_text:
            errors.append(f"{script}: direct historical host-read guard missing")
        elif first_host_operation >= 0 and guard_index > first_host_operation:
            errors.append(f"{script}: host-read guard occurs after host access")

    mutation_text = _read(BLOCKED_MUTATION_SCRIPT)
    block_index = mutation_text.find("Blocked: Heimserver is retired")
    first_mutation = min(
        (index for token in ("mkdir -p", "chmod ", "install ") if (index := mutation_text.find(token)) >= 0),
        default=-1,
    )
    if block_index < 0 or "exit 2" not in mutation_text:
        errors.append(f"{BLOCKED_MUTATION_SCRIPT}: retired mutation block missing")
    elif first_mutation >= 0 and block_index > first_mutation:
        errors.append(f"{BLOCKED_MUTATION_SCRIPT}: retired mutation block occurs after mutation")

    result = {
        "schemaVersion": 1,
        "kind": "retired_reference_contract",
        "checkedDocuments": checked,
        "indexedHistoricalDocuments": len(indexed_documents - ACTIVE_REPOSITORY_DOCUMENTS),
        "discoveredHistoricalDocuments": len(historical_documents),
        "errors": errors,
        "status": "valid" if not errors else "invalid",
    }
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
