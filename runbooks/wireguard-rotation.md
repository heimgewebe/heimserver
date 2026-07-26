---
id: runbook-wireguard-rotation
role: runbooks
status: deprecated
canonicality: explanatory
doc_type: runbook
title: Historical WireGuard Rotation Runbook
summary: Historische Anleitung für die frühere WireGuard-Schlüsselrotation
last_reviewed: 2026-07-26
depends_on: []
verifies_with: []
---

> **Historische Referenz — nicht ausführen.** Dieses Dokument bewahrt einen früheren Stand. Es besitzt keine heutige Runtime-, Netzwerk-, Deployment-, Recovery- oder Infrastrukturautorität. Aktuelle Wahrheit liegt in `heimgewebe/infra` und frischen Runtime-Reads; eine Reaktivierung erfordert einen neuen Bureau-Task und einen dienstgebundenen Infra-Vertrag.

# Historical Runbook: WireGuard Rotation

> **Status: historical / migration-state**
>
> WireGuard ist im Zielmodell nicht mehr primäres Access-Modell.
> Dieses Runbook bleibt als Legacy-/Rollback-Referenz bestehen.
> Primärer Migrationspfad: `runbooks/tailscale-migration.md`.

## Ziel
Keys rotieren, ohne dass Git jemals private Keys sieht.

## Früher verwendeter Secrets-Pfad
- `/etc/heimserver/secrets/wireguard/`

## Grobablauf (Server)

1) Backup (lokal, nicht ins Repo)
- Sicherung des aktuellen `/etc/wireguard/wg0.conf` (falls genutzt)
- Sicherung der Peer-Konfigurationen

2) Neue Server Keys erzeugen

    umask 077
    wg genkey | tee /etc/heimserver/secrets/wireguard/wg0.key | wg pubkey > /etc/heimserver/secrets/wireguard/wg0.pub

3) wg0.conf aus Template rendern
- Template: `security/templates/wireguard/wg0.conf.tmpl`
- Ergebnis: `/etc/wireguard/wg0.conf` (oder dein Zielpfad)
- PrivateKey aus `/etc/heimserver/secrets/wireguard/wg0.key` einfügen

4) Peers
- Pro Peer: neues Keypair im secrets-Pfad erzeugen
- Client bekommt NUR seine Client-Konfig (mit seinem PrivateKey)

5) Restart & Verifikation
- `systemctl restart wg-quick@wg0` (wenn so betrieben)
- `wg show`
- `bash ops/checks/preflight.sh`

## Repo-Regel
- PrivateKey darf in keinem getrackten File stehen.
- Templates bleiben key-frei.
