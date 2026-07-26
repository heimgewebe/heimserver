---
id: ops-runbook-leitstand-gateway
role: runbooks
status: deprecated
canonicality: explanatory
doc_type: runbook
title: Historical Leitstand Gateway Runbook
summary: Historische Betriebsbeschreibung des früheren Leitstand-Gateways auf Heimserver
last_reviewed: 2026-07-26
depends_on: []
verifies_with: []
---

> **Historische Referenz — nicht ausführen.** Dieses Dokument bewahrt einen früheren Stand. Es besitzt keine heutige Runtime-, Netzwerk-, Deployment-, Recovery- oder Infrastrukturautorität. Aktuelle Wahrheit liegt in `heimgewebe/infra` und frischen Runtime-Reads; eine Reaktivierung erfordert einen neuen Bureau-Task und einen dienstgebundenen Infra-Vertrag.

# Historical Ops Runbook: Leitstand Gateway

## Historical canonicality

Dieses Dokument war die kanonische operative Quelle für das frühere Leitstand-Gateway auf Heimserver und besitzt heute keine Betriebsautorität.

Frühere abgeleitete Darstellungen sollten auf dieses Runbook verweisen. Diese historische Beziehung begründet heute keine Verweis-, Sync- oder Betriebsanforderung.

## Synchronisation

Änderungen an diesem Runbook galten früher als führend. Heute begründet es weder eine Sync-Pflicht noch eine operative Änderung; aktuelle Gateway-Wahrheit muss aus dem zuständigen aktiven Repository und frischen Runtime-Reads stammen.

Historischer Scope: früherer Gateway-Betrieb für die Leitstand-UI; diese Aussage beschreibt keinen aktuellen Runtime-Status.

## Status

Historischer Snapshot: Die Leitstand-API war damals nicht Bestandteil des Gateway-Betriebs.

## Historische Architektur

Früheres Ziel: **ein Gateway, damals nur UI (Leitstand)**.
Weltgewebe war optional und hätte einen Upstream sowie eine explizite Aktivierung erfordert.

## Frühere Non-Goals

- Kein direkter Containerzugriff
- Kein öffentlicher Internetzugang
- Kein API-Routing

## Frühere Acceptance Criteria

Die folgenden Befehle dokumentieren ausschließlich die damalige Verifikation und sind nicht auszuführen:

1. **Redirect Check:** Erwartet wurde `308 Permanent Redirect` auf HTTPS.
2. **UI Check:** Erwartet wurde `200 OK` über den damaligen internen CA-Pfad.
3. **Optionaler Health Check:** Erwartet wurde, sofern bereitgestellt, `200 OK`; dies war nicht vertraglich.
4. **Public Exposure Guard:** Der damalige Zielzustand erlaubte nur LAN/WireGuard, keinen öffentlichen Zugriff.

## Historische DNS-Konfiguration

Die DNS-Einträge wurden über Pi-hole-Templates bereitgestellt.

**Frühere Schritte:**
1. Das Template `infra/pihole/99-heimgewebe.conf.example` wurde in die damalige Pi-hole-Konfiguration kopiert.
2. `<GATEWAY_IP>` wurde durch die damalige Heimserver-IP ersetzt.

Für Weltgewebe wurde optional das historische Template `infra/pihole/optional/99-weltgewebe.conf.example` im selben früheren Ablauf verwendet.

## Historische Caddy-Konfiguration

Die damalige Konfiguration sollte mit `infra/caddy/Caddyfile.prod` übereinstimmen.

```caddy
http://leitstand.heimgewebe.home.arpa {
  redir https://leitstand.heimgewebe.home.arpa{uri} 308
}

https://leitstand.heimgewebe.home.arpa {
  encode zstd gzip
  # Der Service-Name entsprach dem damaligen Compose-Service.
  # see infra/compose/compose.prod.yml
  reverse_proxy leitstand:3000
  tls internal
}
```

## Historischer Root-Redirect

Zusätzlich war damals ein Root-Redirect vorgesehen:

```caddy
http://heimgewebe.home.arpa {
  redir https://leitstand.heimgewebe.home.arpa{uri} 308
}

https://heimgewebe.home.arpa {
  redir https://leitstand.heimgewebe.home.arpa{uri} 308
  tls internal
}
```
