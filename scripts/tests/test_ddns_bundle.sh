#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
BUNDLE="$ROOT/scripts/heimberry/install_weltgewebe_ddns.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$BUNDLE" --help >/dev/null

PROGRAM="$TMP/root/usr/local/sbin/weltgewebe-ddns"
SERVICE="$TMP/root/etc/systemd/system/weltgewebe-ddns.service"
TIMER="$TMP/root/etc/systemd/system/weltgewebe-ddns.timer"
CONFIG="$TMP/root/etc/weltgewebe-ddns"

set +e
DEFAULT_OUTPUT="$(DESTDIR="$TMP/root" "$BUNDLE" 2>&1)"
DEFAULT_STATUS=$?
set -e
[[ "$DEFAULT_STATUS" -eq 2 ]]
grep -Fq "Blocked: Heimserver is retired" <<<"$DEFAULT_OUTPUT"
[[ ! -e "$TMP/root" ]]

set +e
LIVE_CHECK_OUTPUT="$(env -u ALLOW_HISTORICAL_HOST_READ "$BUNDLE" --check 2>&1)"
LIVE_CHECK_STATUS=$?
set -e
[[ "$LIVE_CHECK_STATUS" -eq 2 ]]
grep -Fq "Blocked: historical host read requires ALLOW_HISTORICAL_HOST_READ=1" <<<"$LIVE_CHECK_OUTPUT"

set +e
RELATIVE_OUTPUT="$(DESTDIR=relative-fixture "$BUNDLE" --check 2>&1)"
RELATIVE_STATUS=$?
set -e
[[ "$RELATIVE_STATUS" -ne 0 ]]
grep -Fq "DESTDIR must be an absolute fixture path" <<<"$RELATIVE_OUTPUT"

ln -s / "$TMP/root-link"
for root_equivalent in / /tmp/.. "$TMP/root-link"; do
  set +e
  ROOT_OUTPUT="$(env -u ALLOW_HISTORICAL_HOST_READ DESTDIR="$root_equivalent" "$BUNDLE" --check 2>&1)"
  ROOT_STATUS=$?
  set -e
  [[ "$ROOT_STATUS" -eq 2 ]]
  grep -Fq "Blocked: historical host read requires ALLOW_HISTORICAL_HOST_READ=1" <<<"$ROOT_OUTPUT"
done

install -d -m 0700 -- "$CONFIG"
install -D -m 0755 -- "$ROOT/scripts/heimberry/weltgewebe_ddns.py" "$PROGRAM"
install -D -m 0644 -- "$ROOT/ops/systemd/weltgewebe-ddns.service" "$SERVICE"
install -D -m 0644 -- "$ROOT/ops/systemd/weltgewebe-ddns.timer" "$TIMER"
DESTDIR="$TMP/root" "$BUNDLE" --check

[[ -x "$PROGRAM" ]]
[[ "$(stat -c '%a' "$PROGRAM")" == "755" ]]
[[ "$(stat -c '%a' "$SERVICE")" == "644" ]]
[[ "$(stat -c '%a' "$TIMER")" == "644" ]]
[[ "$(stat -c '%a' "$CONFIG")" == "700" ]]
[[ ! -e "$TMP/root/etc/systemd/system/timers.target.wants/weltgewebe-ddns.timer" ]]

cmp --silent "$ROOT/scripts/heimberry/weltgewebe_ddns.py" "$PROGRAM"
cmp --silent "$ROOT/ops/systemd/weltgewebe-ddns.service" "$SERVICE"
cmp --silent "$ROOT/ops/systemd/weltgewebe-ddns.timer" "$TIMER"

rm -f -- "$PROGRAM"
ln -s /bin/true "$PROGRAM"
set +e
ESCAPE_OUTPUT="$(DESTDIR="$TMP/root" "$BUNDLE" --check 2>&1)"
ESCAPE_STATUS=$?
set -e
[[ "$ESCAPE_STATUS" -ne 0 ]]
grep -Fq "fixture path escapes DESTDIR" <<<"$ESCAPE_OUTPUT"
rm -f -- "$PROGRAM"
install -D -m 0755 -- "$ROOT/scripts/heimberry/weltgewebe_ddns.py" "$PROGRAM"

if grep -q '^ConditionFileIsExecutable=' "$SERVICE"; then
  echo "unexpected executable condition" >&2
  exit 1
fi
grep -q '^ConditionPathExists=/etc/weltgewebe-ddns/ENABLE_RETIRED_RUNTIME$' "$SERVICE"
grep -q '^ConditionPathExists=/etc/weltgewebe-ddns/ENABLE_RETIRED_RUNTIME$' "$TIMER"
grep -q '^TimeoutStartSec=360$' "$SERVICE"

if grep -q '^systemctl start weltgewebe-ddns.service$' "$BUNDLE"; then
  echo "legacy activation command must not remain" >&2
  exit 1
fi
if grep -q '^systemctl enable --now weltgewebe-ddns.timer$' "$BUNDLE"; then
  echo "legacy timer enable command must not remain" >&2
  exit 1
fi
grep -q '^  systemctl daemon-reload$' "$BUNDLE"
grep -q '^  systemctl disable --now weltgewebe-ddns.timer$' "$BUNDLE"
grep -Fq "  rm -f -- \"\$CONFIG_DIR/ENABLE_RETIRED_RUNTIME\"" "$BUNDLE"

for blocked_mode in --activate --retire; do
  set +e
  BLOCKED_OUTPUT="$(DESTDIR="$TMP/root" "$BUNDLE" "$blocked_mode" 2>&1)"
  BLOCKED_STATUS=$?
  set -e
  [[ "$BLOCKED_STATUS" -eq 2 ]]
  grep -Fq "Blocked: Heimserver is retired" <<<"$BLOCKED_OUTPUT"
done

printf '\n# drift\n' >> "$PROGRAM"
if DESTDIR="$TMP/root" "$BUNDLE" --check >/dev/null 2>&1; then
  echo "expected --check to reject a drifted staging tree" >&2
  exit 1
fi

echo "weltgewebe DDNS bundle tests passed"
