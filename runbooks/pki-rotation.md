---
id: runbook-pki-rotation
role: runbooks
status: deprecated
canonicality: explanatory
doc_type: runbook
title: Historical PKI Rotation Runbook
summary: Historische Anleitung für die frühere Heimserver-PKI-Rotation
last_reviewed: 2026-07-26
depends_on: []
verifies_with: []
---

> **Historische Referenz — nicht ausführen.** Dieses Dokument bewahrt einen früheren Stand. Es besitzt keine heutige Runtime-, Netzwerk-, Deployment-, Recovery- oder Infrastrukturautorität. Aktuelle Wahrheit liegt in `heimgewebe/infra` und frischen Runtime-Reads; eine Reaktivierung erfordert einen neuen Bureau-Task und einen dienstgebundenen Infra-Vertrag.

# Historical Runbook: PKI / Caddy internal CA Rotation

## Ziel
CA/Cert-Management dokumentieren, ohne Root-Keys zu versionieren.

## Früher verwendeter Secrets-Pfad
- `/etc/heimserver/secrets/pki/`

## Früheres Vorgehen (historisch)

1) Bestandsaufnahme
- Wo speichert Caddy seine PKI (Data Dir / Volume)?
- Welche Hostnames sind relevant (z. B. `leitstand.lan`)?

2) Rotation planen
- Downtime-Fenster (klein)
- Client Trust (z. B. iPad) aktualisieren, falls nötig

3) Umsetzung
- PKI state bleibt im Volume (nicht im Repo)
- Optional: Export der CA public chain (ohne private key) für Clients

4) Verifikation
- Zugriff im LAN/WG ok
- Kein :2019
- Kein 443/udp (wenn QUIC nicht genutzt)

## Repo-Regel
- Keine CA private keys, keine Caddy state dumps in Git.
