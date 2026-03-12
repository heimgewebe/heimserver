---
id: ops-runbook-weltgewebe-stack
role: runbooks
status: active
canonicality: canonical
doc_type: runbook
title: Weltgewebe Stack Runbook
summary: Operations for Weltgewebe app stack
last_reviewed: 2026-03-07
depends_on:
  - architecture/naming.md
  - architecture/networking/port-matrix.md
---

# Ops Runbook: Weltgewebe Stack

Scope: Kanonische Wahrheit und operative Checks für den Weltgewebe-Stack auf dem Heimserver.

## 1. Architektur-Entscheidung: Vollwertiger Stack & Lokale UI

**Vorheriger Drift:**
Docs, Runbook und Health sprachen teilweise NATS an, der effektive Weltgewebe-Prod-Stack lief aber als API-/Proxy-Minimum ohne NATS. UI-Requests wurden teilweise als primär über Cloudflare Pages beschrieben.

**Neue kanonische Wahrheit:**
Weltgewebe auf dem Heimserver ist ein vollwertiger Stack mit:
- Service `api`
- Service `nats` (JetStream)
- Service `db`
- Edge/Proxy-Integration wie bisher, wobei der **Heimserver die primäre Frontdoor für die UI ist**.

NATS ist nicht optionaler Alttext, sondern Teil der beabsichtigten Betriebsrealität.

Die statische UI wird lokal aus dem Build-Pfad (`/opt/weltgewebe/apps/web/build`) über den Edge-Caddy ausgeliefert.
Cloudflare Pages fungiert, wenn überhaupt, nur noch als sekundärer Spiegel.

Die URLs verhalten sich wie folgt:
- `https://weltgewebe.home.arpa`: Liefert die statische UI.
- `https://weltgewebe.home.arpa/api/*`: Proxied zur Weltgewebe-API.
- `https://api.weltgewebe.home.arpa`: Optionaler, separater API-Endpunkt.

**Ziel:**
Contract (Weltgewebe-Repo), Deploy, Health und operative Doku wieder deckungsgleich machen. Heimgewebe und Weltgewebe bleiben strikt getrennt. Das Heimserver-Repo ist nur für Enforcement und Betrieb zuständig.

## 2. Minimaler Gesundheitscheck (Health/Smoke)

Der Stack muss vollständig laufen.
Primärer, service-orientierter Check:

```bash
docker compose -p weltgewebe ps
```

Erwartete Services:
- `api` (Up/Healthy)
- `nats` (Up - *Hinweis: Healthcheck falls im Upstream definiert*)
- `db` (Up)

Schneller Quick-Check (Containerebene):

```bash
docker ps --format '{{.Names}} {{.Status}}' | grep weltgewebe
```

### 2.1 API-Healthcheck (Kanonisch)

Jegliche direkten API-Healthchecks über lokale Host-Ports (z.B. `127.0.0.1:8081/health/ready`) sind strikt verboten.
Gemäß der [Port-Matrix](../architecture/networking/port-matrix.md) gehört Port 8081 exklusiv dem Pi-hole (FTL), und Weltgewebe-Apps dürfen generell keine Host-Ports binden (internal-only).

Prüfe die Health der Weltgewebe-API ausschließlich über Edge/FQDN oder Docker-native Checks:

a) **Edge/FQDN-Check (empfohlen):**

Auf Heimservern mit `tls internal` muss dem `curl`-Aufruf entweder das Caddy-CA-Zertifikat mitgegeben werden (via `--cacert`), oder die CA muss systemweit als vertrauenswürdig hinterlegt sein.

*(Hinweis: Der Pfad `/opt/heimgewebe/edge/certs/caddy-local-root.crt` existiert aktuell ebenfalls und enthält dieselbe Root-CA, ist aber nicht der kanonische Referenzpfad im Runbook.)*

```bash
curl -fsS --cacert /opt/heimgewebe/edge/edge-ca.crt https://api.weltgewebe.home.arpa/health/ready
# oder (falls als Alias)
curl -fsS --cacert /opt/heimgewebe/edge/edge-ca.crt https://weltgewebe.home.arpa/api/health/ready
```

b) **Docker-native Checks (innerhalb des Netzwerks):**
```bash
API_CID="$(docker compose -p weltgewebe ps -q api)"
docker inspect --format='{{json .State.Health}}' "$API_CID"
```

## 3. Symptome bei fehlendem NATS

Woran man erkennt, dass NATS fehlt oder nicht korrekt läuft:
- **API-Logs:** Der `api`-Service wirft Connection-Errors oder Timeouts beim Versuch, auf NATS zuzugreifen (z.B. `dial tcp: lookup nats`).
- **Funktionalität:** Events oder asynchrone Jobs werden nicht verarbeitet, State-Updates schlagen fehl.
- **Docker Status:** `docker inspect --format='{{json .State.Status}}' $(docker compose -p weltgewebe ps -q nats)` liefert nicht `"running"` (oder Container fehlt komplett).

**Lösung:**
Sicherstellen, dass im Weltgewebe-Repo (Contract) der `nats` Service definiert und provisioniert ist und beim Deployment auf dem Heimserver mit hochgefahren wird.
