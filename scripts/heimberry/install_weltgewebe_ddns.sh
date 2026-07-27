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

usage() {
  cat <<'EOF'
Usage: scripts/heimberry/install_weltgewebe_ddns.sh [--check | --retire]

Only --check remains available and performs a read-only file drift comparison.
The default install path, --retire and the former --activate path are blocked
before file or service mutation because this repository is retired. Live --check
also requires ALLOW_HISTORICAL_HOST_READ=1. DESTDIR may point to an existing,
absolute, non-root fixture; every resolved check target must remain below it.
EOF
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

block_historical_host_read() {
  printf '%s\n' "Blocked: historical host read requires ALLOW_HISTORICAL_HOST_READ=1" >&2
  exit 2
}

block_root_destdir() {
  printf '%s\n' "Blocked: DESTDIR resolves to the live root; remove DESTDIR for an explicitly authorized live --check" >&2
  exit 2
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

if [[ -n "$DESTDIR" ]]; then
  [[ "$DESTDIR" == /* ]] || fail "DESTDIR must be an absolute fixture path"
  [[ -d "$DESTDIR" ]] || fail "DESTDIR fixture root must exist for --check"
  DESTDIR="$(realpath -e -- "$DESTDIR")" || fail "unable to canonicalize DESTDIR fixture root"
  [[ "$DESTDIR" != "/" ]] || block_root_destdir
elif [[ "$ALLOW_HISTORICAL_HOST_READ" != "1" ]]; then
  block_historical_host_read
fi

PROGRAM_PATH="$DESTDIR/usr/local/sbin/weltgewebe-ddns"
SERVICE_PATH="$DESTDIR/etc/systemd/system/weltgewebe-ddns.service"
TIMER_PATH="$DESTDIR/etc/systemd/system/weltgewebe-ddns.timer"
CONFIG_DIR="$DESTDIR/etc/weltgewebe-ddns"

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

resolve_checked_path() {
  local target=$1
  local resolved

  if [[ -z "$DESTDIR" ]]; then
    printf '%s\n' "$target"
    return 0
  fi

  resolved="$(realpath -e -- "$target")" || fail "fixture path missing or unresolved: $target"
  case "$resolved" in
    "$DESTDIR"/*) printf '%s\n' "$resolved" ;;
    *) fail "fixture path escapes DESTDIR: $target -> $resolved" ;;
  esac
}

compare_file() {
  local source=$1
  local target=$2
  local resolved

  resolved="$(resolve_checked_path "$target")"
  [[ -f "$resolved" ]] || fail "installed file missing: $target"
  cmp --silent -- "$source" "$resolved" || fail "installed file differs: $target"
  printf '%s\n' "$resolved"
}

check_installation() {
  local resolved_program
  local resolved_service
  local resolved_timer
  local resolved_config

  resolved_program="$(compare_file "$SOURCE_PROGRAM" "$PROGRAM_PATH")"
  resolved_service="$(compare_file "$SOURCE_SERVICE" "$SERVICE_PATH")"
  resolved_timer="$(compare_file "$SOURCE_TIMER" "$TIMER_PATH")"
  resolved_config="$(resolve_checked_path "$CONFIG_DIR")"

  [[ "$(stat -c '%a' "$resolved_program")" == "755" ]] || fail "unexpected mode on $PROGRAM_PATH"
  [[ "$(stat -c '%a' "$resolved_service")" == "644" ]] || fail "unexpected mode on $SERVICE_PATH"
  [[ "$(stat -c '%a' "$resolved_timer")" == "644" ]] || fail "unexpected mode on $TIMER_PATH"
  [[ -d "$resolved_config" ]] || fail "configuration directory missing: $CONFIG_DIR"
  [[ "$(stat -c '%a' "$resolved_config")" == "700" ]] || fail "unexpected mode on $CONFIG_DIR"

  if [[ -z "$DESTDIR" ]]; then
    [[ "$(stat -c '%u:%g' "$resolved_program")" == "0:0" ]] || fail "unexpected owner on $PROGRAM_PATH"
    [[ "$(stat -c '%u:%g' "$resolved_service")" == "0:0" ]] || fail "unexpected owner on $SERVICE_PATH"
    [[ "$(stat -c '%u:%g' "$resolved_timer")" == "0:0" ]] || fail "unexpected owner on $TIMER_PATH"
    [[ "$(stat -c '%u:%g' "$resolved_config")" == "0:0" ]] || fail "unexpected owner on $CONFIG_DIR"
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
