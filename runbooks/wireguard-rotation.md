# Runbook: WireGuard Rotation (ohne Keys in Git)

> **Status: historical / migration-state**
>
> WireGuard ist im Zielmodell nicht mehr primäres Access-Modell.
> Dieses Runbook bleibt als Legacy-/Rollback-Referenz bestehen.
> Primärer Migrationspfad: `runbooks/tailscale-migration.md`.

## Ziel
Keys rotieren, ohne dass Git jemals private Keys sieht.

## Kanonischer Secrets-Pfad
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
