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

## 1.1 Basemap / PMTiles Bereitstellung (Hosting)

Die Bereitstellung des Basemap-Artefakts (`.pmtiles`) erfolgt deployment-abhängig über die Weltgewebe-Compose- und Caddy-Konfiguration. Der Heimserver stellt den Betriebs-/Serve-Kontext bereit; der konkrete Artefaktpfad auf dem Host ergibt sich aus dem aktuell deployten Weltgewebe-Stand.

**Wichtig:** Dies bedeutet *nicht*, dass der Weltgewebe-Client in Produktion bereits standardmäßig darauf zurückgreift (die client-seitige Standardschaltung `local-sovereign` bleibt getrennt im Weltgewebe-Repo). Dies belegt lediglich, dass die Hosting-Bereitschaft auf Infrastruktur-Ebene gegeben ist. Die tatsächliche Betriebsreife/E2E-Nachweis der lokalen Basemap-Nutzung ist weiterhin offen.

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

## 4. Symptome bei fehlender oder fehlerhafter Basemap-/PMTiles-Bereitstellung

Woran man erkennt, dass das PMTiles-Artefakt nicht korrekt bereitgestellt oder ausgeliefert wird:
- **Client-Fehler:** Die Karte lädt keine Hintergrundkacheln, im Netzwerk-Tab des Browsers erscheinen 404-Fehler für `.pmtiles`-Requests.
- **Fehlendes Artefakt:** Die Datei existiert nicht im gemounteten Host-Pfad.

**Diagnose:**

1. **Mount-Pfad ermitteln:** Prüfe in der `docker-compose.yml` (bzw. in den definierten Volumes/Mounts) des Weltgewebe-Deployments, welcher Host-Pfad für das PMTiles-Artefakt verwendet wird.
2. **Artefakt-Prüfung:** Prüfe, ob die `.pmtiles`-Datei im dort definierten Host-Pfad tatsächlich vorhanden ist (z.B. via `ls -la <ermittelter-Pfad>`).
3. **Serving-Pfad ermitteln:** Prüfe in der Caddy-Konfiguration des Weltgewebe-Deployments, unter welcher Route das Artefakt ausgeliefert wird.
4. **Caddy-Auslieferung testen:** Führe einen Abruf gegen diesen expliziten Pfad durch (inklusive konkretem Dateinamen):
```bash
curl -I --cacert /opt/heimgewebe/edge/edge-ca.crt https://weltgewebe.home.arpa/<ermittelter-Caddy-Pfad-inklusive-Dateiname>
```
*(Hinweis: Erwartet wird ein HTTP 200 OK)*
