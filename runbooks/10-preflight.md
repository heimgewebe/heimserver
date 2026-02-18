# Runbook: Preflight vor/nach Änderungen

## Ziel
Drift schnell erkennen, bevor er „real“ wird.

## Schritte

1) Repo Preflight

    bash ops/checks/preflight.sh

2) Wenn WARN auftaucht
- Ursache ermitteln
- Wenn sich die Realität (Ports/Container) geändert hat: [`runtime.md`](../runtime/runtime.md) aktualisieren.
- Wenn sich Regeln/Architektur geändert haben: [`constitution.md`](../architecture/constitution.md) (oder naming/network in `../architecture/`) aktualisieren.
- Falls Regression: zurückrollen oder fixen

## Minimaler Abschluss
- Keine Host-Listener auf 0.0.0.0:80/443
- Kein :2019
- DOCKER-USER sinnvoll
- wg handshake plausibel
