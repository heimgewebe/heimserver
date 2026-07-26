# heimserver

> **Status: außer Betrieb / historische Referenz.** Der physische Heimserver besitzt keine aktive Rolle, Exposition, Autorität oder Recovery-Abhängigkeit. Die aktuelle Infrastrukturverfassung liegt in [`heimgewebe/infra@e1245b5…:INFRA_CONSTITUTION.md`](https://github.com/heimgewebe/infra/blob/e1245b502393edcdb42d0f20317c8a5a2c2defbe/INFRA_CONSTITUTION.md).

Dieses private Repository bleibt erhalten, damit frühere Betriebsverträge, Sicherheitsüberlegungen, Runbooks und Runtime-Belege nachvollziehbar bleiben. Es ist kein Ops-Orakel, kein Service-Layer und keine Quelle für aktuellen Laufzeitstatus. Historische Anweisungen dürfen nicht ohne einen neuen, dienstgebundenen und reviewten Vertrag ausgeführt werden.

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

Das Repo bewahrt die frühere Trennung zwischen Norm, beobachteter Realität und Handlung als historische Evidenz:

1.  **[`architecture/`](architecture/)** (Die Verfassung)
    *   Normative Regeln, Netzplanung, Naming-Konventionen.
    *   Hier steht, *wie die frühere Architektur beabsichtigt war*.
2.  **[`runtime/`](runtime/)** (Die Realität)
    *   Der beobachtete Ist-Zustand des Systems (Ports, Container, Routen).
    *   Hier stehen zeitgebundene frühere Beobachtungen; sie belegen keinen aktuellen Laufzustand.
3.  **[`operations/`](operations/)** (Die Handlung)
    *   Protokolle, Checks und operative Eingriffe.
    *   Hier stehen frühere Eingriffe; sie sind ohne neuen Vertrag nicht auszuführen.

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

## Prüfung der historischen Referenz

Vor Änderungen werden ausschließlich repositorylokale, nichtmutierende Konsistenzchecks ausgeführt. Serverinitialisierung, Secrets-Erzeugung, Deployment, Netzwerk- oder Dienständerung sind nicht Teil des Standardpfads.

## Repo-Intention

Dieses Repo ist eine historische Referenz:
- Historische Aussagen bleiben datei- und commitgebunden nachvollziehbar.
- Aktuelle Infrastrukturwahrheit kommt aus `heimgewebe/infra` und frischen Runtime-Reads.
- Templates bleiben erhalten; Schlüssel und Secrets bleiben außerhalb von Git.
