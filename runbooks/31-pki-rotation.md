# Runbook: PKI / Caddy internal CA Rotation (ohne private keys in Git)

## Ziel
CA/Cert-Management dokumentieren, ohne Root-Keys zu versionieren.

## Kanonischer Secrets-Pfad
- `/etc/heimserver/secrets/pki/`

## Vorgehen (konzeptionell)

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
