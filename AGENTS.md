# AGENTS.md — Heimserver Ops Repo (Entry Point)

Ziel: Dieses Repo dient primär als Orientierung + Operationalisierung für Agents.

## Kanon (was ist „wahr“?)

- **Kanonische Runtime (IST-Zustand):** `heimserver.runtime.md`
- **Kanonischer Kontext (Architektur):** `heimserver.constitution.md`
- **Kanonische Netz-Architektur:** `heimserver.network.md`
- **Kanonische Namens-Architektur:** `heimserver.naming.md`
- **Operative Checks (Wahrheitsquelle):** `ops/checks/preflight.sh`
- **Operatives Protokoll (Betrieb):** `heimserver.operations.md`
- **Runbooks (Handlungsabläufe):** `runbooks/`
- **Templates (keine Secrets):** `security/templates/`

## Repo-Policy (Privat vs. Public)

**Status:** Dauerhaft privat.
**Regel:** Reale IPs, Subnetze und Pfade sind im Repo erlaubt, um die operative Realität abzubilden.
**Verbot:** Niemals Keys, Secrets, Zertifikate (Private Keys), Logs oder unredacted Snapshots committen.
**Guardrail:** Repo darf niemals public geschaltet werden; wenn doch, ist das ein Security Incident.

## Grundsatz: Secrets-Shadow-Pfad (außerhalb von Git)

**NIEMALS** Private Keys/Root-CA Keys in Git committen.
Stattdessen: fester Pfad auf dem Server.

Kanonischer Pfad (Server):
- `/etc/heimserver/secrets` (empfohlen, root, 0700)

Layout:
- `/etc/heimserver/secrets/wireguard/wg0.key`
- `/etc/heimserver/secrets/wireguard/peers/ipad.key`
- `/etc/heimserver/secrets/pki/root-ca.key`

Repo enthält nur:
- Dateinamen-Konventionen
- Templates
- Runbooks
- Checks

## Minimal-Workflow (für Agents)

1) **Preflight laufen lassen**
   - `bash ops/checks/preflight.sh`

2) **Drift prüfen**
   - Vergleiche Output mit `heimserver.runtime.md`
   - Caddy Admin 2019 darf nicht lauschen
   - DOCKER-USER: allow LAN/WG, drop rest für 80/443

3) **Wenn Änderungen nötig**
   - Dokument: `heimserver.runtime.md` (bei Drift) oder `heimserver.constitution.md` (bei Architektur) aktualisieren
   - Runbook referenzieren (oder anlegen)

## Hard Rules

- Keine Secrets in Git (Keys, CA private keys, WireGuard private keys, .env)
- Keine Audit-Snapshots in Git (nur Referenz-Pfade)
- Keine produktiven Overrides (`docker-compose.override.yml`) in Git

## Common Paths (Konventionen)

- Checks: `ops/checks/`
- Hooks: `ops/hooks/`
- Templates: `security/templates/`
- Runbooks: `runbooks/`
- Manifest: `manifest/`

## Drift-Trigger (immer Preflight)

- Änderung an Docker/Compose
- Änderung an Firewall/iptables/netfilter-persistent
- Änderung an WireGuard peers/routes
- Änderung an Caddy/TLS/Hostnames
- Änderung an DNS (FritzBox/Resolver)
