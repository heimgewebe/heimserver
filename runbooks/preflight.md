---
id: runbook-preflight
role: runbooks
status: deprecated
canonicality: explanatory
doc_type: runbook
title: Historical Preflight Runbook
summary: Historische Anleitung für frühere Heimserver-Driftprüfungen
last_reviewed: 2026-07-26
depends_on: []
verifies_with: []
---

> **Historische Referenz — nicht ausführen.** Dieses Dokument bewahrt einen früheren Stand. Es besitzt keine heutige Runtime-, Netzwerk-, Deployment-, Recovery- oder Infrastrukturautorität. Aktuelle Wahrheit liegt in `heimgewebe/infra` und frischen Runtime-Reads; eine Reaktivierung erfordert einen neuen Bureau-Task und einen dienstgebundenen Infra-Vertrag.

# Historical Runbook: Preflight vor/nach Änderungen

## Ziel
Drift schnell erkennen, bevor er „real“ wird.

## Frühere Schritte

1) Früherer Host-Preflight

    bash ops/checks/preflight.sh

2) Wenn WARN auftaucht
- Ursache ermitteln
- Wenn sich die Realität (Ports/Container) geändert hat: [`runtime.md`](../runtime/runtime.md) aktualisieren.
- Wenn sich Regeln/Architektur geändert haben: [`constitution.md`](../architecture/constitution.md), [`naming.md`](../architecture/naming.md) oder [`network.md`](../architecture/network.md) aktualisieren.
- Falls Regression: zurückrollen oder fixen

## Minimaler Abschluss
- Keine Host-Listener auf 0.0.0.0:80/443
- Kein :2019
- DOCKER-USER sinnvoll
- wg handshake plausibel
