# Repo Purpose (Kanonisch)

## Wofür existiert dieses Repo?

1) **Orientierung**: schneller, eindeutiger Einstieg in den Heimserver-Kontext.
2) **Operationalisierung**: reproduzierbare Checks + Runbooks statt „Wissen im Kopf“.
3) **Drift-Resistenz**: Änderungen erzwingen Updates am Kontext + Preflight.

## Was gehört hier rein?

- Kontext: `heimserver.constitution.md`
- Checks: `ops/checks/*`
- Runbooks: `runbooks/*`
- Templates (ohne Secrets): `security/templates/*`
- Beispielkonfigurationen: `*.example`

## Was gehört NICHT rein?

- Private Keys (WireGuard, PKI Root/Intermediate)
- Vollständige Audit-Snapshots (nur Referenzen/Paths)
- Logs/DBs/Backups/Exports
- Produktive Overrides

## Agent-First Regeln

- Jede kritische Aussage hat einen Check.
- Jede Recovery-Aktion hat ein Runbook.
- Pfade sind stabil und werden nicht „kreativ“ umbenannt.
