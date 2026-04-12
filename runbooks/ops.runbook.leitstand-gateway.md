# Ops Runbook: Leitstand Gateway

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
2. **UI Check:** `curl -fsS -I --cacert /opt/heimgewebe/edge/edge-ca.crt https://leitstand.heimgewebe.home.arpa/` → Muss `200 OK` liefern.
3. **Health Check:** `curl -fsS -I --cacert /opt/heimgewebe/edge/edge-ca.crt https://leitstand.heimgewebe.home.arpa/health` → Muss `200 OK` liefern.
4. **Public Exposure Guard:** Ein Aufruf über das öffentliche Internet darf die Domain nicht auflösen oder keine Verbindung herstellen können (LAN-only).

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
