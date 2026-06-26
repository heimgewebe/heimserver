# Edge Synchronization Runbook
⛔️ OPERATIONAL RUNBOOK

**Target:** `/opt/heimgewebe/edge`
**Source:** `edge/` (Repo Template)

## Sync Gate-Reihenfolge (`sync_caddyfile.sh`)

Der Sync ist fail-closed. Kann ein Sicherheitszustand nicht eindeutig belegt werden,
bricht das Skript ab, bevor es die Live-Datei verändert.

| Gate | Was wird geprüft | Exit bei Fehler |
|------|------------------|-----------------|
| 1. Lock + Eingaben + Snapshot | Exklusiver Sync-Lock; Live-Datei und Kandidat sind vorhanden; der Kandidat wird sofort einmal in ein privates temporäres Verzeichnis kopiert und gehasht | 1 oder 2 |
| 2. Container-ID-Auflösung | Compose-Service-ID `caddy` löst auf genau eine konkrete Container-ID auf | 1 bei Mehrdeutigkeit, 2 bei fehlender Diagnose |
| 3. Anfangs-Hashes | Host-Live-Hash entspricht `EXPECTED_LIVE_SHA256`; Container-Datei derselben Container-ID hat denselben Hash | 1 oder 2 |
| 4. Snapshot-Syntax | `caddy validate` läuft mit lokal vorhandenem `caddy:2.8.4` gegen den privaten Kandidaten-Snapshot | 1 oder 2 |
| 5. Genau ein Adapt | `caddy adapt` läuft genau einmal; stdout wird als private JSON-Datei gespeichert, stderr getrennt protokolliert; JSON ist nicht leer und parsebar | 2 |
| 6. Kanonischer Caddy-Vertrag | `validate_caddy_contract.py --adapted-json` prüft Admin-Bindung, Hostmatrix, Upstream `weltgewebe-api:8080`, `/api`-Redirect, Basemap, Cache-/CORS-Header und Routenreihenfolge | 1 oder 2 |
| 7. Admin-Boundary | `check_admin_boundary.sh --container-id "$CADDY_CONTAINER_ID"` prüft dieselbe Containerinstanz: Admin lokal erreichbar, Listener nur `127.0.0.1:2019`, kein 2019-Port in Compose, Runtime oder Host | 1 oder 2 |
| 8. Rechecks vor Mutation | Kandidaten-Snapshot und Adapt-JSON werden erneut gehasht; Live-Hash wird wiederholt; Compose-Service-ID muss weiterhin dieselbe Container-ID ergeben | 1 oder 2 |
| 9. Backup + In-place-Write | Backup-Pfad wird kollisionsfrei angelegt; der Backup-Hash muss dem geprüften Anfangs-Hash entsprechen; erst danach werden ausschließlich die Snapshot-Bytes mit `cat > "$LIVE_FILE"` in den bestehenden Bind-Mount-Inode geschrieben | 1, 2 oder 255 |
| 10. Post-Write-Beweis | Container-ID wird erneut bestätigt; Host-Hash und Container-Hash müssen dem Snapshot entsprechen; `caddy validate` läuft im Container gegen `/etc/caddy/Caddyfile` | 1, 2 oder 255 |

### Exit-Codes

| Exit | Bedeutung |
|------|-----------|
| 0 | Erfolg oder dokumentierter No-op |
| 1 | Vertragsverletzung oder erkannte Drift |
| 2 | Diagnose nicht möglich, z. B. fehlendes Tool, fehlendes lokales Caddy-Image, ungültiges JSON, Docker-Startfehler oder keine Container-ID |
| 255 | Rollback wurde versucht, konnte aber nicht vollständig bewiesen werden |

`caddy validate`-Syntaxfehler werden im Sync als Vertragsverletzung (`1`) behandelt. Kann Docker den
Validierungscontainer nicht starten, etwa mit Exit `125`, ist das ein Diagnosefehler (`2`). `caddy adapt`-Fehler,
leere Adapt-Ausgabe und nicht parsebares JSON sind ebenfalls Diagnosefehler (`2`). Validatoren und
Boundary-Guard geben ihre dokumentierten Exits `1` und `2` weiter.

> [!IMPORTANT]
> `sync_caddyfile.sh` führt **keinen** `caddy reload` durch. Ein Reload ist ein separater manueller Schritt
> und erst nach vollständigem Sync- oder Rollback-Beweis zulässig.

Die Einführung oder Verschärfung einer Content-Security-Policy ist bewusst nicht Teil dieses Patches. Sie
benötigt einen separaten Browser-/Runtime-Beweis für API-, Karten-, Bild- und Worker-Ressourcen.

## Begriffe

* **Compose-Service-ID:** `caddy`, der Schlüssel im Compose-File.
* **Containername:** `edge-caddy`, ein lesbares Runtime-Label.
* **Container-ID:** die konkrete Docker-ID, die `docker compose ... ps --quiet caddy` liefert. Der Sync bindet
  alle Runtimeprüfungen (`docker exec`, `docker inspect`) an diese ID und bricht ab, wenn Compose später eine
  andere ID liefert.

## Deployment Procedure

### 1. Prepare Host Directory

```bash
sudo mkdir -p /opt/heimgewebe/edge/certs
sudo chown -R root:root /opt/heimgewebe/edge
sudo mkdir -p /opt/weltgewebe/apps/web/build
# sudo chown -R myuser:mygroup /opt/weltgewebe/apps/web/build
```

### 2. Verify External Networks

```bash
docker network inspect edge || docker network create edge
docker network inspect heimnet || docker network create heimnet
docker network inspect weltgewebe_default >/dev/null 2>&1 || {
  echo "CRITICAL: weltgewebe_default missing! Edge compose will fail."
  exit 1
}
```

### 3. Synchronize Templates

```bash
sudo cp edge/docker-compose.yml.template /opt/heimgewebe/edge/docker-compose.yml

# Use a SHA-256 recorded during an earlier explicit review or deployment
# manifest. Do not derive the expected value from the current live file here.
REVIEWED_LIVE_SHA256="<reviewed-live-sha256>"
[[ "$REVIEWED_LIVE_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "Set REVIEWED_LIVE_SHA256 to the previously reviewed live hash." >&2
  exit 1
}
sudo EXPECTED_LIVE_SHA256="$REVIEWED_LIVE_SHA256" \
  bash scripts/edge/sync_caddyfile.sh
```

The sync writes only the validated private snapshot to `/opt/heimgewebe/edge/Caddyfile`.
It does not write from the original candidate path after the snapshot has been created.

### 4. Customize Runtime

If a deployment needs local overrides, create them on the host. Do not commit productive overrides or secrets.

## Admin-API-Vertrag

Die Caddy-Admin-API ist für kontrollierten Reload und Rollback zulässig, aber ausschließlich an
`127.0.0.1:2019` innerhalb der geprüften Container-ID gebunden. Port `2019` darf weder hostseitig
veröffentlicht noch über Docker-Netze erreichbar sein.

```bash
sudo EDGE_DIR=/opt/heimgewebe/edge \
  COMPOSE_FILE=/opt/heimgewebe/edge/docker-compose.yml \
  bash scripts/edge/check_admin_boundary.sh
```

## Verification

Resolve and bind the current container ID:

```bash
set -euo pipefail

EDGE_DIR=/opt/heimgewebe/edge
COMPOSE_FILE=/opt/heimgewebe/edge/docker-compose.yml
CADDY_SERVICE=caddy
CADDY_CONTAINER_ID="$(
  sudo docker compose --project-directory "$EDGE_DIR" -f "$COMPOSE_FILE" ps --quiet "$CADDY_SERVICE"
)"
test -n "$CADDY_CONTAINER_ID"
test "$(printf '%s\n' "$CADDY_CONTAINER_ID" | sed '/^[[:space:]]*$/d' | wc -l)" -eq 1
```

Host/container hash and Caddy validation:

```bash
HOST_HASH="$(sudo sha256sum /opt/heimgewebe/edge/Caddyfile | awk '{print $1}')"
CONTAINER_HASH="$(
  sudo docker exec "$CADDY_CONTAINER_ID" sha256sum /etc/caddy/Caddyfile | awk '{print $1}'
)"
test "$HOST_HASH" = "$CONTAINER_HASH"
sudo docker exec "$CADDY_CONTAINER_ID" \
  caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile
```

Port and Admin boundary:

```bash
sudo docker inspect "$CADDY_CONTAINER_ID" --format '{{json .NetworkSettings.Ports}}'
ss -H -ltn | awk '$4 ~ /:2019$/ {print; found=1} END {exit found ? 1 : 0}'
sudo docker exec "$CADDY_CONTAINER_ID" sh -ec '
  wget -qO- -T 3 http://127.0.0.1:2019/config/ >/dev/null ||
  curl --fail --silent --max-time 3 http://127.0.0.1:2019/config/ >/dev/null
'
```

Endpoint and log checks:

```bash
curl -I https://weltgewebe.home.arpa
curl -I https://weltgewebe.net
sudo docker logs edge-caddy --tail 100
sudo docker exec "$CADDY_CONTAINER_ID" getent hosts weltgewebe-api
```

## Manual Reload

Only run this after the sync or rollback proof above has passed. Resolve Compose again immediately before
reload and require the same single container ID that was verified:

```bash
set -euo pipefail

RELOAD_CONTAINER_ID="$(
  sudo docker compose --project-directory "$EDGE_DIR" -f "$COMPOSE_FILE" ps --quiet "$CADDY_SERVICE"
)"
test -n "$RELOAD_CONTAINER_ID"
test "$(printf '%s\n' "$RELOAD_CONTAINER_ID" | sed '/^[[:space:]]*$/d' | wc -l)" -eq 1
test "$RELOAD_CONTAINER_ID" = "$CADDY_CONTAINER_ID"

sudo docker exec "$RELOAD_CONTAINER_ID" \
  caddy reload \
    --adapter caddyfile \
    --config /etc/caddy/Caddyfile
```

## In-place Rollback

If a post-sync check aborts, the script attempts rollback automatically. For manual rollback:

```bash
set -euo pipefail

EDGE_DIR=/opt/heimgewebe/edge
COMPOSE_FILE=/opt/heimgewebe/edge/docker-compose.yml
CADDY_SERVICE=caddy
BACKUP_FILE="/opt/heimgewebe/edge/Caddyfile.bak.<suffix>"

CADDY_CONTAINER_ID="$(
  sudo docker compose --project-directory "$EDGE_DIR" -f "$COMPOSE_FILE" ps --quiet "$CADDY_SERVICE"
)"
test -n "$CADDY_CONTAINER_ID"
test "$(printf '%s\n' "$CADDY_CONTAINER_ID" | sed '/^[[:space:]]*$/d' | wc -l)" -eq 1
BACKUP_HASH="$(sudo sha256sum "$BACKUP_FILE" | awk '{print $1}')"

sudo sh -c 'cat "$1" > "$2"' sh "$BACKUP_FILE" /opt/heimgewebe/edge/Caddyfile

HOST_HASH="$(sudo sha256sum /opt/heimgewebe/edge/Caddyfile | awk '{print $1}')"
test "$HOST_HASH" = "$BACKUP_HASH"

ROLLBACK_CONTAINER_ID="$(
  sudo docker compose --project-directory "$EDGE_DIR" -f "$COMPOSE_FILE" ps --quiet "$CADDY_SERVICE"
)"
test -n "$ROLLBACK_CONTAINER_ID"
test "$(printf '%s\n' "$ROLLBACK_CONTAINER_ID" | sed '/^[[:space:]]*$/d' | wc -l)" -eq 1
test "$ROLLBACK_CONTAINER_ID" = "$CADDY_CONTAINER_ID"

CONTAINER_HASH="$(
  sudo docker exec "$ROLLBACK_CONTAINER_ID" sha256sum /etc/caddy/Caddyfile | awk '{print $1}'
)"
test "$CONTAINER_HASH" = "$BACKUP_HASH"

sudo docker exec "$ROLLBACK_CONTAINER_ID" \
  caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile

sudo docker logs edge-caddy --tail 100
curl -I https://weltgewebe.home.arpa
```

Reload only after these rollback checks pass. Immediately before that reload, resolve Compose once more.
The strict shell mode below guarantees that any failed identity check aborts before `caddy reload`:

```bash
set -euo pipefail

RELOAD_CONTAINER_ID="$(
  sudo docker compose --project-directory "$EDGE_DIR" -f "$COMPOSE_FILE" ps --quiet "$CADDY_SERVICE"
)"
test -n "$RELOAD_CONTAINER_ID"
test "$(printf '%s\n' "$RELOAD_CONTAINER_ID" | sed '/^[[:space:]]*$/d' | wc -l)" -eq 1
test "$RELOAD_CONTAINER_ID" = "$ROLLBACK_CONTAINER_ID"

sudo docker exec "$RELOAD_CONTAINER_ID" \
  caddy reload \
    --adapter caddyfile \
    --config /etc/caddy/Caddyfile
```

## Cross-Repo-Konkurrenzfall

Weltgewebe kann den Heimserver-Edge-Container über seinen Edge-Refresh-Pfad neu erstellen
(`docker compose -p edge -f docker-compose.yml up -d --force-recreate` unter `/opt/heimgewebe/edge`).
Dieser Heimserver-Sync erkennt einen solchen parallelen Recreate über Container-ID-Rechecks vor Backup/Write
und nach dem Write fail-closed. Ein gemeinsamer hostweiter Lock zwischen Weltgewebe-Edge-Recreate und
Heimserver-Caddy-Sync ist damit nicht bewiesen und bleibt ein separater Folgeauftrag.

Der Folgeauftrag muss einen gemeinsamen Lockpfad, die Lockreihenfolge, Timeout/Diagnose bei belegtem Lock und
eine zyklusfreie Repo-Zuständigkeit definieren.

## Drift Management

Any permanent change to the host Caddyfile must be backported to `edge/Caddyfile.template`, unless it contains secrets.
