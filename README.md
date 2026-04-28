# heimserver

Dieses Repo ist das operative Rückgrat (Ops-Orakel) für das Heimnetz.
Der Repository-Name bleibt historisch `heimserver`, die Zielsemantik ist jedoch ein Layer-Modell:

- **Heimberry = Truth Layer** (DNS/Resolver/Truth)
- **Heimserver = Service Layer** (Caddy, interne PKI, App-Container)
- **Heim-PC = Interaction Layer**
- **iPad = Access Layer**

Siehe kanonisch: [`architecture/heimnetz-2026.md`](architecture/heimnetz-2026.md).

## Einstiegspunkte

Die Orientierung in diesem Repository ist in drei Ebenen strukturiert:

1. **Dokumentations-Einstieg (für Menschen):**
   [`docs/index.md`](docs/index.md) - Die vollständige Übersicht aller Architekturen, Entscheidungen und Runbooks.

2. **Agentischer Einstieg (für Agents):**
   [`AGENTS.md`](AGENTS.md) - Arbeitsgrenzen, Policies und kanonische Wahrheitsquellen für autonome Systeme.

3. **Maschinenlesbare Repo-Metadaten:**
   - `repo.meta.yaml` - Die strikte Repo-Identität und Strukturwahrheit.
   - `agent-policy.yaml` - Maschinenlesbare Änderungsgrenzen und Guards.

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

    git ls-files | grep -E "(audit|rules\\.v4|rules\\.v6|\\.env|wireguard|\\.key|\\.pem)" || echo "OK"

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

    bash ops/checks/redact_snapshot.sh ops/audit/snapshots/<ts>

## Repo-Intention

Dieses Repo ist ein Ops-Orakel:
- Doku ist nur dann wertvoll, wenn sie durch Checks **verifizierbar** ist.
- Templates statt Schlüssel: Komfort ohne Selbstsabotage.
