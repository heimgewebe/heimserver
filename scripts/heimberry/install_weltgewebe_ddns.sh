#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"

SOURCE_PROGRAM="$SCRIPT_DIR/weltgewebe_ddns.py"
SOURCE_SERVICE="$REPO_ROOT/ops/systemd/weltgewebe-ddns.service"
SOURCE_TIMER="$REPO_ROOT/ops/systemd/weltgewebe-ddns.timer"

DESTDIR="${DESTDIR:-}"
ACTIVATE=0
CHECK_ONLY=0
RETIRE=0
ALLOW_ANY_HOST="${WELTGEWEBE_DDNS_ALLOW_ANY_HOST:-0}"
ALLOW_HISTORICAL_HOST_READ="${ALLOW_HISTORICAL_HOST_READ:-0}"

PROGRAM_PATH="$DESTDIR/usr/local/sbin/weltgewebe-ddns"
SERVICE_PATH="$DESTDIR/etc/systemd/system/weltgewebe-ddns.service"
TIMER_PATH="$DESTDIR/etc/systemd/system/weltgewebe-ddns.timer"
CONFIG_DIR="$DESTDIR/etc/weltgewebe-ddns"


usage() {
  cat <<'EOF'
Usage: scripts/heimberry/install_weltgewebe_ddns.sh [--check | --retire]

Only --check remains available and performs a read-only file drift comparison.
The default install path, --retire and the former --activate path are blocked
before file or service mutation because this repository is retired. Live --check
also requires ALLOW_HISTORICAL_HOST_READ=1. DESTDIR may be set for isolated
--check fixtures without live-host authorization.
EOF
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf 'INFO: %s\n' "$*"
}

while (($# > 0)); do
  case "$1" in
    --activate)
      ((ACTIVATE += 1))
      ;;
    --check)
      ((CHECK_ONLY += 1))
      ;;
    --retire)
      ((RETIRE += 1))
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

if ((ACTIVATE > 1 || CHECK_ONLY > 1 || RETIRE > 1 || ACTIVATE + CHECK_ONLY + RETIRE > 1)); then
  fail "choose exactly one of --activate, --check or --retire"
fi

if ((CHECK_ONLY == 0)); then
  printf '%s\n' "Blocked: Heimserver is retired; DDNS installation and service mutation are unavailable from this repository" >&2
  exit 2
fi

if [[ -z "$DESTDIR" && "$ALLOW_HISTORICAL_HOST_READ" != "1" ]]; then
  printf '%s\n' "Blocked: historical host read requires ALLOW_HISTORICAL_HOST_READ=1" >&2
  exit 2
fi

for source in "$SOURCE_PROGRAM" "$SOURCE_SERVICE" "$SOURCE_TIMER"; do
  [[ -f "$source" ]] || fail "source file missing: $source"
done

if [[ -z "$DESTDIR" ]]; then
  [[ $EUID -eq 0 ]] || fail "installation on the live host requires root"

  if [[ "$ALLOW_ANY_HOST" != "1" && "$(hostname -s)" != "heimberry" ]]; then
    fail "refusing live installation outside heimberry; use WELTGEWEBE_DDNS_ALLOW_ANY_HOST=1 only for a reviewed exception"
  fi
elif ((RETIRE == 1)); then
  fail "--retire is unavailable with DESTDIR"
fi

if ((RETIRE == 1)); then
  rm -f -- "$CONFIG_DIR/ENABLE_RETIRED_RUNTIME"
  systemctl daemon-reload
  systemctl disable --now weltgewebe-ddns.timer
  systemctl reset-failed weltgewebe-ddns.service || true
  if systemctl is-enabled --quiet weltgewebe-ddns.timer; then
    fail "legacy timer is still enabled"
  fi
  if systemctl is-active --quiet weltgewebe-ddns.timer; then
    fail "legacy timer is still active"
  fi
  log "legacy DynDNS runtime retired; credentials preserved"
  exit 0
fi

compare_file() {
  local source=$1
  local target=$2

  [[ -f "$target" ]] || fail "installed file missing: $target"
  cmp --silent -- "$source" "$target" || fail "installed file differs: $target"
}

check_installation() {
  compare_file "$SOURCE_PROGRAM" "$PROGRAM_PATH"
  compare_file "$SOURCE_SERVICE" "$SERVICE_PATH"
  compare_file "$SOURCE_TIMER" "$TIMER_PATH"

  [[ "$(stat -c '%a' "$PROGRAM_PATH")" == "755" ]] || fail "unexpected mode on $PROGRAM_PATH"
  [[ "$(stat -c '%a' "$SERVICE_PATH")" == "644" ]] || fail "unexpected mode on $SERVICE_PATH"
  [[ "$(stat -c '%a' "$TIMER_PATH")" == "644" ]] || fail "unexpected mode on $TIMER_PATH"
  [[ -d "$CONFIG_DIR" ]] || fail "configuration directory missing: $CONFIG_DIR"
  [[ "$(stat -c '%a' "$CONFIG_DIR")" == "700" ]] || fail "unexpected mode on $CONFIG_DIR"

  if [[ -z "$DESTDIR" ]]; then
    [[ "$(stat -c '%u:%g' "$PROGRAM_PATH")" == "0:0" ]] || fail "unexpected owner on $PROGRAM_PATH"
    [[ "$(stat -c '%u:%g' "$SERVICE_PATH")" == "0:0" ]] || fail "unexpected owner on $SERVICE_PATH"
    [[ "$(stat -c '%u:%g' "$TIMER_PATH")" == "0:0" ]] || fail "unexpected owner on $TIMER_PATH"
    [[ "$(stat -c '%u:%g' "$CONFIG_DIR")" == "0:0" ]] || fail "unexpected owner on $CONFIG_DIR"
  fi

  log "installed files match the repository sources"
}

if ((CHECK_ONLY == 1)); then
  check_installation
  log "activation state intentionally not checked by --check"
  exit 0
fi

install -d -m 0700 -- "$CONFIG_DIR"
install -D -m 0755 -- "$SOURCE_PROGRAM" "$PROGRAM_PATH"
install -D -m 0644 -- "$SOURCE_SERVICE" "$SERVICE_PATH"
install -D -m 0644 -- "$SOURCE_TIMER" "$TIMER_PATH"

if [[ -z "$DESTDIR" ]]; then
  chown root:root -- "$PROGRAM_PATH" "$SERVICE_PATH" "$TIMER_PATH" "$CONFIG_DIR"
fi

check_installation

if ((ACTIVATE == 0)); then
  log "installation complete; timer not activated"
  exit 0
fi

fail "unreachable activation path"
