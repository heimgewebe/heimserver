#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

expect_blocked() {
  local label="$1"
  local marker="$2"
  shift 2
  local output
  local status
  set +e
  output="$(env -u ALLOW_HISTORICAL_HOST_READ "$@" 2>&1)"
  status=$?
  set -e
  [ "$status" -ne 0 ] || fail "$label unexpectedly succeeded"
  printf '%s\n' "$output" | grep -Fq "$marker" || fail "$label did not emit retirement marker"
  printf 'PASS: %s blocked with status %s\n' "$label" "$status"
}

expect_blocked "direct preflight" "Blocked: historical host read" bash ops/checks/preflight.sh
expect_blocked "direct snapshot" "Blocked: historical host read" env SNAPSHOT_DIR="$tmp/snapshot" bash ops/checks/snapshot.sh
[ ! -e "$tmp/snapshot" ] || fail "direct snapshot created output before guard"
expect_blocked "direct secrets initialization" "Blocked: Heimserver is retired" bash ops/init-secrets-path.sh
expect_blocked "make preflight" "Blocked: historical host read" make preflight
expect_blocked "make snapshot" "Blocked: historical host read" env SNAPSHOT_DIR="$tmp/make-snapshot" make snapshot
[ ! -e "$tmp/make-snapshot" ] || fail "make snapshot created output before guard"
expect_blocked "make secrets" "Blocked: Heimserver is retired" make secrets

if command -v just >/dev/null 2>&1; then
  expect_blocked "just preflight" "Blocked: historical host read" just preflight
  expect_blocked "just snapshot" "Blocked: historical host read" env SNAPSHOT_DIR="$tmp/just-snapshot" just snapshot
  [ ! -e "$tmp/just-snapshot" ] || fail "just snapshot created output before guard"
  expect_blocked "just secrets" "Blocked: Heimserver is retired" just secrets
fi

printf 'All retired entrypoint guards passed.\n'
