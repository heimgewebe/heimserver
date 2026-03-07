---
id: ops-runbook-weltgewebe-stack
role: runbooks
status: canonical
last_reviewed: 2026-03-01
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
- API (`weltgewebe-api`)
- NATS/JetStream (`weltgewebe-nats`)
- DB (`weltgewebe-db`)
- Edge/Proxy-Integration wie bisher

NATS ist nicht optionaler Alttext, sondern Teil der beabsichtigten Betriebsrealität.

**Ziel:**
Contract (Weltgewebe-Repo), Deploy, Health und operative Doku wieder deckungsgleich machen. Heimgewebe und Weltgewebe bleiben strikt getrennt. Das Heimserver-Repo ist nur für Enforcement und Betrieb zuständig.

## 2. Minimaler Gesundheitscheck (Health/Smoke)

Der Stack muss vollständig laufen (Quick-Check):

```bash
docker ps --format '{{.Names}} {{.Status}}' | grep weltgewebe
```

Erwartete Container:
- `weltgewebe-api` (Up/Healthy)
- `weltgewebe-nats` (Up/Healthy)
- `weltgewebe-db` (Up)

## 3. Symptome bei fehlendem NATS

Woran man erkennt, dass NATS fehlt oder nicht korrekt läuft:
- **API-Logs:** `weltgewebe-api` wirft Connection-Errors oder Timeouts beim Versuch, auf NATS zuzugreifen (z.B. `dial tcp: lookup weltgewebe-nats`).
- **Funktionalität:** Events oder asynchrone Jobs werden nicht verarbeitet, State-Updates schlagen fehl.
- **Docker Health:** `docker inspect --format='{{json .State.Health.Status}}' weltgewebe-nats` liefert `unhealthy` oder Container existiert nicht.

**Lösung:**
Sicherstellen, dass im Weltgewebe-Repo (Contract) `weltgewebe-nats` definiert und provisioniert ist und beim Deployment auf dem Heimserver mit hochgefahren wird.
