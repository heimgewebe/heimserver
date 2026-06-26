#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
BUNDLE="$ROOT/scripts/heimberry/install_weltgewebe_ddns.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$BUNDLE" --help >/dev/null

DESTDIR="$TMP/root" "$BUNDLE"
DESTDIR="$TMP/root" "$BUNDLE" --check

PROGRAM="$TMP/root/usr/local/sbin/weltgewebe-ddns"
SERVICE="$TMP/root/etc/systemd/system/weltgewebe-ddns.service"
TIMER="$TMP/root/etc/systemd/system/weltgewebe-ddns.timer"
CONFIG="$TMP/root/etc/weltgewebe-ddns"

[[ -x "$PROGRAM" ]]
[[ "$(stat -c '%a' "$PROGRAM")" == "755" ]]
[[ "$(stat -c '%a' "$SERVICE")" == "644" ]]
[[ "$(stat -c '%a' "$TIMER")" == "644" ]]
[[ "$(stat -c '%a' "$CONFIG")" == "700" ]]
[[ ! -e "$TMP/root/etc/systemd/system/timers.target.wants/weltgewebe-ddns.timer" ]]

cmp --silent "$ROOT/scripts/heimberry/weltgewebe_ddns.py" "$PROGRAM"
cmp --silent "$ROOT/ops/systemd/weltgewebe-ddns.service" "$SERVICE"
cmp --silent "$ROOT/ops/systemd/weltgewebe-ddns.timer" "$TIMER"

if grep -q '^ConditionFileIsExecutable=' "$SERVICE"; then
  echo "unexpected executable condition" >&2
  exit 1
fi
if grep -q '^ConditionPathExists=' "$SERVICE"; then
  echo "unexpected path condition" >&2
  exit 1
fi
grep -q '^TimeoutStartSec=360$' "$SERVICE"

service_start_line="$(grep -n '^systemctl start weltgewebe-ddns.service$' "$BUNDLE" | cut -d: -f1)"
timer_enable_line="$(grep -n '^systemctl enable --now weltgewebe-ddns.timer$' "$BUNDLE" | cut -d: -f1)"
[[ -n "$service_start_line" && -n "$timer_enable_line" ]]
((service_start_line < timer_enable_line))

if DESTDIR="$TMP/root" "$BUNDLE" --activate >/dev/null 2>&1; then
  echo "expected --activate to be rejected with DESTDIR" >&2
  exit 1
fi

printf 'sentinel\n' > "$CONFIG/existing-file"
DESTDIR="$TMP/root" "$BUNDLE"
[[ "$(cat "$CONFIG/existing-file")" == "sentinel" ]]

printf '\n# drift\n' >> "$PROGRAM"
if DESTDIR="$TMP/root" "$BUNDLE" --check >/dev/null 2>&1; then
  echo "expected --check to reject a drifted staging tree" >&2
  exit 1
fi

echo "weltgewebe DDNS bundle tests passed"
