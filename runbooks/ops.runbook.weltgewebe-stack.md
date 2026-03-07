---
id: ops-runbook-weltgewebe-stack
role: runbooks
status: canonical
last_reviewed: 2026-03-07
depends_on:
  - architecture/naming.md
  - architecture/networking/port-matrix.md
---

# Ops Runbook: Weltgewebe Stack

Scope: Kanonische Wahrheit und operative Checks für den Weltgewebe-Stack auf dem Heimserver.

## 1. Architektur-Entscheidung: Vollwertiger Stack

**Vorheriger Drift:**
Docs, Runbook und Health sprachen teilweise NATS an, der effektive Weltgewebe-Prod-Stack lief aber als API-/Proxy-Minimum ohne NATS.

**Neue kanonische Wahrheit:**
Weltgewebe auf dem Heimserver ist ein vollwertiger Stack mit:
- Service `api`
- Service `nats` (JetStream)
- Service `db`
- Edge/Proxy-Integration wie bisher

NATS ist nicht optionaler Alttext, sondern Teil der beabsichtigten Betriebsrealität.

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

## 3. Symptome bei fehlendem NATS

Woran man erkennt, dass NATS fehlt oder nicht korrekt läuft:
- **API-Logs:** Der `api`-Service wirft Connection-Errors oder Timeouts beim Versuch, auf NATS zuzugreifen (z.B. `dial tcp: lookup nats`).
- **Funktionalität:** Events oder asynchrone Jobs werden nicht verarbeitet, State-Updates schlagen fehl.
- **Docker Status:** `docker inspect --format='{{json .State.Status}}' $(docker compose -p weltgewebe ps -q nats)` liefert nicht `"running"` (oder Container fehlt komplett).

**Lösung:**
Sicherstellen, dass im Weltgewebe-Repo (Contract) der `nats` Service definiert und provisioniert ist und beim Deployment auf dem Heimserver mit hochgefahren wird.
