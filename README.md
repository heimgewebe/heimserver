# heimserver

Kanonischer Kontext liegt in [`architecture/constitution.md`](architecture/constitution.md).

Primärer Einstieg für Agents: [`AGENTS.md`](AGENTS.md).

## Struktur & Hierarchie

Das Repo folgt einer strikten Trennung zwischen Norm (Soll), Realität (Ist) und Handlung (Tun):

1.  **[`architecture/`](architecture/)** (Die Verfassung)
    *   Normative Regeln, Netzplanung, Naming-Konventionen.
    *   Hier steht, *wie es sein muss*.
2.  **[`runtime/`](runtime/)** (Die Realität)
    *   Der beobachtete Ist-Zustand des Systems (Ports, Container, Routen).
    *   Hier steht, *was aktuell läuft*.
3.  **[`operations/`](operations/)** (Die Handlung)
    *   Protokolle, Checks und operative Eingriffe.
    *   Hier steht, *was getan wird*.

Zusätzlich:
*   `runbooks/`: Konkrete Handlungsanweisungen (Step-by-Step).
*   `ops/`: Skripte und Checks zur Automatisierung.

## Declarative Repo Structure

The repository structure is declared in:
`manifest/repo-index.yaml`

Only canonical docs should be listed in `manifest/repo-index.yaml`.

A human-readable system overview is generated in:
[`SYSTEM_MAP.md`](SYSTEM_MAP.md)

Do not edit SYSTEM_MAP.md manually.
Regenerate via:
`python3 scripts/generate-system-map.py`

## Safety Checks (vor jedem Push)

Keine sensiblen Dateien getrackt?

    git ls-files | grep -E "(audit|server-facts|rules\\.v4|rules\\.v6|\\.env|wireguard|\\.key|\\.pem)" || echo "OK"

Repo-Policy:
- Repo bleibt privat.
- Audit-Snapshots liegen im Repo-Baum unter `ops/audit/snapshots/`, sind aber git-ignored (nicht getrackt).

## Quickstart

Hooks installieren (empfohlen):

    bash ops/install-hooks.sh

Preflight laufen lassen:

    bash ops/checks/preflight.sh

Secrets-Pfad initialisieren (Server):

    sudo bash ops/init-secrets-path.sh

Snapshot redacted kopieren (vor dem Teilen prüfen):

    bash ops/checks/redact_snapshot.sh /home/alex/server-facts/audit-snapshots/<ts>

## Repo-Intention

Dieses Repo ist ein Ops-Orakel:
- Doku ist nur dann wertvoll, wenn sie durch Checks **verifizierbar** ist.
- Templates statt Schlüssel: Komfort ohne Selbstsabotage.
