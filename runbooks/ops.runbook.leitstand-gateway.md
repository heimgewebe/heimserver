# Ops Runbook: Leitstand Gateway

## Canonicality

Dieses Dokument ist die kanonische operative Quelle für das Leitstand Gateway auf dem Heimserver.

Abgeleitete Darstellungen (z. B. im Leitstand-Repository) dürfen keine eigenständigen operativen Details zum Gateway-Betrieb auf dem Heimserver enthalten und müssen auf dieses Runbook verweisen.

## Synchronisation

Änderungen an diesem Runbook gelten als führend. Abgeleitete Dokumente (wie im Leitstand-Repository) müssen angepasst werden, bevor operative Änderungen am Gateway als vollständig abgeschlossen gelten. Im PR-Review-Prozess ist aktiv zu prüfen, ob ein Sync-PR im Leitstand-Repo erforderlich ist.

Scope: Operativer Gateway-Betrieb für Leitstand-UI. API-Routing ist derzeit nicht aktiv.

## Status

Die Leitstand-API ist derzeit nicht Bestandteil des Gateway-Betriebs (kein Reverse Proxy Upstream definiert).

## Architektur

Ziel: **ein Gateway, aktuell nur UI (Leitstand)**.
Weltgewebe ist optional (erfordert Upstream + explizite Aktivierung).

## Non-Goals

- Kein direkter Containerzugriff
- Kein öffentlicher Internetzugang
- Kein API-Routing

## Acceptance Criteria

Zur Verifikation der Gateway-Konfiguration (auszuführen von einem Client im LAN/WireGuard):

1. **Redirect Check:** `curl -fsS -I http://leitstand.heimgewebe.home.arpa` → Muss `308 Permanent Redirect` auf HTTPS liefern.
2. **UI Check:** `curl -fsS -I --cacert <EDGE_CA_PATH> https://leitstand.heimgewebe.home.arpa/` (z.B. `/opt/heimgewebe/edge/edge-ca.crt`) → Muss `200 OK` liefern.
3. **Optionaler Health Check (nur falls vom Leitstand-Service bereitgestellt):** `curl -fsS -I --cacert <EDGE_CA_PATH> https://leitstand.heimgewebe.home.arpa/health` → Erwartet `200 OK` (nicht-contractual, andernfalls ignorieren).
4. **Public Exposure Guard:** Ein Aufruf über das öffentliche Internet darf nicht öffentlich auflösbar oder erreichbar sein (nur LAN/WireGuard).

## DNS Konfiguration

Die DNS-Einträge werden über Pi-hole Templates bereitgestellt.

**Schritte:**
1. Kopiere `infra/pihole/99-heimgewebe.conf.example` in die Pi-hole Konfiguration (z.B. `/etc/dnsmasq.d/` im Volume).
2. Ersetze `<GATEWAY_IP>` durch die IP des Heimservers (z.B. `192.168.178.46`).

Für Weltgewebe (Optional):
1. Kopiere `infra/pihole/optional/99-weltgewebe.conf.example` in die Pi-hole Konfiguration.
2. Ersetze `<GATEWAY_IP>`.

## Caddy Konfiguration

Die Konfiguration muss mit `infra/caddy/Caddyfile.prod` übereinstimmen.

```caddy
http://leitstand.heimgewebe.home.arpa {
  redir https://leitstand.heimgewebe.home.arpa{uri} 308
}

https://leitstand.heimgewebe.home.arpa {
  encode zstd gzip
  # Service-Name muss dem Compose-Service entsprechen.
  # see infra/compose/compose.prod.yml
  reverse_proxy leitstand:3000
  tls internal
}
```

## Root Redirect

Zusätzlich ist ein Root-Redirect aktiv:

```caddy
http://heimgewebe.home.arpa {
  redir https://leitstand.heimgewebe.home.arpa{uri} 308
}

https://heimgewebe.home.arpa {
  redir https://leitstand.heimgewebe.home.arpa{uri} 308
  tls internal
}
```
