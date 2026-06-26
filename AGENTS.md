# AGENTS.md

## Zweck
Ziel: Dieses Repo dient primär als Orientierung + Operationalisierung für Agents. Es enthält explizite Policy-Regeln in `agent-policy.yaml` und Repo-Metadaten in `repo.meta.yaml`.
Dieses Repo ist das operative Rückgrat (Ops-Orakel) für den Heimserver und verwaltet die Infrastruktur des Weltgewebe Application Stacks.

## Zuerst lesen
Dieses Repo folgt einer strikten Trennung zwischen Norm (Soll) und Realität (Ist).
- **Repo-Policy (Privat vs. Public):** Dauerhaft privat. Reale IPs, Subnetze und Pfade sind im Repo erlaubt, um die operative Realität abzubilden. Niemals Keys, Secrets, Zertifikate (Private Keys), Logs oder unredacted Snapshots committen. Repo darf niemals public geschaltet werden; wenn doch, ist das ein Security Incident.
- **Secrets-Shadow-Pfad:** Private Keys/Root-CA Keys liegen niemals in Git, sondern auf dem Server (z.B. `/etc/heimserver/secrets`). Repo enthält nur Dateinamen-Konventionen, Templates, Runbooks und Checks.
- **Minimal-Workflow für Agents:**
  1) Preflight laufen lassen: `bash ops/checks/preflight.sh`
  2) Drift prüfen: Vergleiche Output mit `runtime/runtime.md`
  3) Wenn Änderungen nötig: Entsprechendes Dokument (`runtime/runtime.md` oder `architecture/constitution.md`) aktualisieren und Runbooks referenzieren.

## Kanonische Quellen
- **Runtime (IST-Zustand):** `runtime/runtime.md`
- **Kontext (Architektur):** `architecture/constitution.md`
- **Netz-Architektur:** `architecture/network.md`
- **Namens-Architektur:** `architecture/naming.md`
- **Operative Checks:** `ops/checks/preflight.sh`
- **Operatives Protokoll:** `operations/operations.md`
- **Runbooks:** `runbooks/`
- **Templates:** `security/templates/`

## Erkennungsregeln
Alle `discovery_roots` in `repo.meta.yaml` werden regelmäßig durch das Repo-Observatorium gescannt. Neue Markdown-Dokumente und Implementierungen werden dabei erkannt und müssen entsprechend eingeordnet werden. Kanonische Dokumente benötigen zwingend YAML Frontmatter (`check_repo_index_consistency.py` erzwingt dies).

## Generierte Dateien
Generierte Übersichten befinden sich unter `docs/_generated/` und in der Datei `SYSTEM_MAP.md`.
Diese Dateien werden automatisch durch Skripte generiert und dürfen niemals manuell editiert werden.

## Sichere Lesepfade
- `README.md`
- `AGENTS.md`
- `repo.meta.yaml`
- `agent-policy.yaml`
- `architecture/`
- `runtime/`
- `runbooks/`
- `docs/`
- `ops/systemd/`
- `manifest/`
- `SYSTEM_MAP.md`

## Geschützte / riskante Pfade
- `architecture/` (Änderungen der Norm)
- `runtime/` (Anpassung der Realität, erfordert immer Snapshot-Beweise)
- `runbooks/` (Operative Anweisungen)
- `manifest/repo-index.yaml`
- `ops/systemd/`
- `docs/`
- Drift-Trigger: Änderungen an Docker/Compose, Firewall/iptables/netfilter-persistent, WireGuard peers/routes, Caddy/TLS/Hostnames, DNS (FritzBox/Resolver).

## Erforderliche Checks
Die Einhaltung der Repo-Regeln wird durch folgende Checks gewährleistet, die zwingend auszuführen sind:
- `bash ops/checks/preflight.sh`
- `python3 scripts/ci/check_repo_index_consistency.py`
- `python3 scripts/ci/check-doc-review-age.py`
- `bash scripts/ci/check-runbook-invariants.sh`
- `python3 -m unittest scripts/tests/test_weltgewebe_ddns.py`
- `bash scripts/tests/test_ddns_bundle.sh`

## Häufige Fallen
- **Secrets in Git:** Keine produktiven Overrides (`docker-compose.override.yml`), `.env` oder unredacted Audit-Snapshots in Git.
- **Port-Ownership Violation:** Port 8081 gehört zwingend Pi-hole. Weltgewebe Container müssen internal-only sein.
- **Caddy Admin API:** Caddy Admin (2019) darf nicht lauschen.
- **Public Edge Exception:** Öffentlich erlaubt sind ausschließlich `weltgewebe.net`, `www.weltgewebe.net` und `api.weltgewebe.net` über Edge-Caddy TCP 80/443. Direkte App-/Admin-/DB-Ports und Heimberry-Ingress bleiben verboten.

## Offene Lücken
- Abweichungen im Dateibaum gegenüber den definierten Roots werden durch `docs/_generated/architecture-drift.md` erfasst.
- Undokumentierte Implementierungen werden in `docs/_generated/doc-coverage.md` gemeldet.
- Fehlen von explizitem Wissen und Glossar-Definitionen wird in `docs/_generated/knowledge-gaps.md` gesammelt.
