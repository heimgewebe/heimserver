# Ops Runbook: Leitstand Gateway

Scope: Caddy Edge Proxy Konfiguration für Leitstand (UI) und API sowie DNS-Einträge.

## Architektur

Ziel: **ein Gateway, aktuell nur UI (Leitstand)**.
API ist deaktiviert (kein Upstream).
Weltgewebe ist optional (erfordert Upstream + explizite Aktivierung).

## DNS Konfiguration

Die DNS-Einträge werden über Pi-hole Templates bereitgestellt.

**Schritte:**
1. Kopiere `infra/pihole/99-heimgewebe.conf.example` nach `infra/pihole/99-heimgewebe.conf` (lokal für Deployment) oder direkt in das Volume.
2. Ersetze `<GATEWAY_IP>` durch die IP des Heimservers (z.B. `192.168.178.46`).

Für Weltgewebe (Optional):
1. Kopiere `infra/pihole/optional/99-weltgewebe.conf.example`.
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
