# Ops Runbook: Leitstand Gateway

Scope: Caddy Edge Proxy Konfiguration für Leitstand (UI) und API.

## Architektur

Ziel: **ein Gateway, aktuell nur UI (Leitstand)**.
API ist vorbereitet, aber noch nicht provisioniert.

## Konfiguration (Snippet)

Die Konfiguration muss mit `infra/caddy/Caddyfile.prod` übereinstimmen:

```caddy
http://leitstand.heimgewebe.home.arpa {
  redir https://leitstand.heimgewebe.home.arpa{uri} 308
}

https://leitstand.heimgewebe.home.arpa {
  encode zstd gzip
  # Service-Name muss dem Compose-Service entsprechen.
  # see infra/compose/compose.prod.yml (or equivalent)
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
