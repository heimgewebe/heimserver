# AGENTS

## Purpose
Dieses Repo dient primär als Orientierung + Operationalisierung für Agents. Es ist das Ops-Orakel für die Heimserver-Infrastruktur.

## Read This First
Beginne immer mit `repo.meta.yaml`, `AGENTS.md` und der durch `scripts/generate-system-map.py` generierten `SYSTEM_MAP.md`. Führe vor jeglichen Änderungen `bash ops/checks/preflight.sh` aus, um den aktuellen Systemzustand gegen den dokumentierten Kanon abzugleichen.

## Canonical Sources
- **Kanonischer Kontext (Architektur):** `architecture/constitution.md`
- **Kanonische Netz-Architektur:** `architecture/network.md`
- **Kanonische Namens-Architektur:** `architecture/naming.md`
- **Kanonische Terminologie:** `architecture/glossary.md`
- **Kanonische Runtime (IST-Zustand):** `runtime/runtime.md`
- **Operative Checks (Wahrheitsquelle):** `ops/checks/preflight.sh`

## Discovery Rules
Neue Markdown-Dateien in den Discovery-Roots (`architecture/`, `runtime/`, `runbooks/`, etc.) werden automatisch gescannt. Wenn eine Datei nicht über `manifest/repo-index.yaml` als kanonisch registriert ist, wird sie als Orphan (verwaist) markiert. Jedes Dokument muss Frontmatter mit Relationen (`depends_on`, `documents`, `implemented_by`, `supersedes`) tragen, um den semantischen Graph zu pflegen.

## Generated Files
- `SYSTEM_MAP.md`: Kanonische Übersicht, abgeleitet aus dem Manifest.
- `docs/_generated/relations.json`: Semantischer Relationengraph.
- `docs/_generated/backlinks.md`: Rückverweise zwischen Dokumenten.
- `docs/_generated/orphans.md`: Liste von Dokumenten ohne Referenzziele.
- `agent-readiness.md`: Status des agentischen Reifegrads.

Diese Dateien dürfen **niemals** manuell editiert werden.

## Safe Read Paths
- `README.md`
- `AGENTS.md`
- `repo.meta.yaml`
- `architecture/`
- `runtime/`
- `runbooks/`
- `manifest/`
- `SYSTEM_MAP.md`

## Guarded / Risky Paths
- `architecture/` (Änderung erfordert Abstimmung mit operations)
- `runtime/runtime.md` (Änderung erfordert Beleg durch preflight.sh oder Commit-Artefakte)
- `ops/checks/` (Ändert Wahrheitsdefinitionen)
- `scripts/ci/` (Ändert Policy-Durchsetzung)
- `manifest/repo-index.yaml` (Definiert Kanon)

**Verbotene Pfade (Forbidden Write Paths):**
- `/etc/heimserver/secrets/`
- `docker-compose.override.yml` (Nur lokal auf dem Server erlaubt)
- `*.key`, `*.pem`, `.env`
- Unredigierte Audit Snapshots (`ops/audit/snapshots/**`)

## Required Checks
- `bash ops/checks/preflight.sh` (Drift und Infrastruktur prüfen)
- `scripts/ci/check-repo-index-consistency.sh` (Struktur und Frontmatter validieren)
- `scripts/ci/check-doc-review-age.py` (Dokumenten-Freshness prüfen)

## Common Traps
- **Splitbrain:** Doku aktualisiert, aber Container/Ports im Host abweichend. Immer Preflight nutzen.
- **Agenten-Regeln missachten:** Geheimnisse in Git committen.
- **Port Conflicts:** Caddy Admin darf nicht lauschen (2019), Port 8081 gehört fest zu Pi-hole.
- **Fehlende Header:** Caddy-Routing verlangt Host-Header bei `curl`-Tests (z. B. `curl -H "Host: weltgewebe.home.arpa"`).

## Open Gaps
- Die Repos (`heimserver`, `weltgewebe`, `leitstand`) sind lose gekoppelt. Semantische Abhängigkeiten über Repos hinweg sind derzeit primär in den Beschreibungen (z. B. im Glossary) erfasst und bedürfen noch robuster, repofremder Verknüpfungsmechanismen.
