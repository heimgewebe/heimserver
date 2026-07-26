# AGENTS.md

## Zweck
Ziel: Dieses Repo dient primär der Orientierung und beweissicheren Erhaltung historischer Heimserver-Verträge. Es enthält explizite Policy-Regeln in `agent-policy.yaml` und Repo-Metadaten in `repo.meta.yaml`.
Dieses Repo ist eine historische private Betriebs- und Vertragsreferenz. Heimserver ist außer Betrieb; das Repository besitzt keine aktive Runtime-, Netzwerk-, Deployment-, Recovery- oder Infrastrukturautorität.

## Aktuelle Autoritätsgrenze

- Kanonischer aktueller Zielzustand: `heimgewebe/infra` `INFRA_CONSTITUTION.md`.
- Heimserver: außer Betrieb; keine aktive Rolle, Exposition oder Autorität.
- Historische Runtime-Belege begründen keine heutige Erreichbarkeit oder Betriebsfreigabe.
- Änderungen dürfen den Host weder in Fleet, SSH, DNS, systemd, Cockpit noch Recovery zurückführen.

## Zuerst lesen
Dieses Repo bewahrt die frühere Trennung zwischen Norm und Realität als historische Evidenz. Aktuelle Infrastrukturwahrheit liegt in `heimgewebe/infra` und in frischen Runtime-Reads.
- **Repo-Policy (Privat vs. Public):** Dauerhaft privat. Reale IPs, Subnetze und Pfade sind im Repo erlaubt, um die operative Realität abzubilden. Niemals Keys, Secrets, Zertifikate (Private Keys), Logs oder unredacted Snapshots committen. Repo darf niemals public geschaltet werden; wenn doch, ist das ein Security Incident.
- **Secrets-Shadow-Pfad:** Private Keys/Root-CA Keys liegen niemals in Git, sondern auf dem Server (z.B. `/etc/heimserver/secrets`). Repo enthält nur Dateinamen-Konventionen, Templates, Runbooks und Checks.
- **Minimal-Workflow für Agents:**
  1) Repository- und Dokumentvertragschecks ausführen.
  2) Historische Aussagen nur gegen ihre gebundene Quelle bewerten; `runtime/` ist kein aktueller Statusfeed.
  3) Keine Runbooks, Deployments, Netzwerk- oder Dienstoperationen aus diesem Repository ausführen. Eine Reaktivierung benötigt einen neuen Bureau-Task, einen dienstgebundenen Infra-Vertrag und frische Runtime-Belege.

## Kanonische Quellen
- **Historische Runtime-Evidenz:** `runtime/runtime.md`
- **Historische Architektur:** `architecture/constitution.md`
- **Netz-Architektur:** `architecture/network.md`
- **Namens-Architektur:** `architecture/naming.md`
- **Historische/Repositorylokale Checks:** `ops/checks/preflight.sh`
- **Historisches Operationsprotokoll:** `operations/operations.md`
- **Historische Runbooks:** `runbooks/`
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
- **Caddy Admin API:** Die Caddy-Admin-API darf weder hostseitig veröffentlicht noch über Container-Netze erreichbar sein. Eine ausschließlich an `127.0.0.1:2019` innerhalb des geprüften Caddy-Containers gebundene Admin-API ist für kontrolliertes Reloading und Rollback zulässig.
- **Public Edge Exception:** Öffentlich erlaubt sind ausschließlich `weltgewebe.net`, `www.weltgewebe.net` und `api.weltgewebe.net` über Edge-Caddy TCP 80/443. Direkte App-/Admin-/DB-Ports und Heimberry-Ingress bleiben verboten.
- **DOCKER-USER Firewall:** LAN/WireGuard bleiben grundsätzlich erlaubt; die eng begrenzte Public-Edge-Ausnahme darf ausschließlich TCP 80/443 zu Edge-Caddy öffnen. Alle anderen direkten Internetpfade werden verworfen.

## Offene Lücken
- Abweichungen im Dateibaum gegenüber den definierten Roots werden durch `docs/_generated/architecture-drift.md` erfasst.
- Undokumentierte Implementierungen werden in `docs/_generated/doc-coverage.md` gemeldet.
- Fehlen von explizitem Wissen und Glossar-Definitionen wird in `docs/_generated/knowledge-gaps.md` gesammelt.
