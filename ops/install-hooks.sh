#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
HOOKS_DIR="$ROOT/.git/hooks"

mkdir -p "$HOOKS_DIR"

install_one() {
  local name="$1"
  local src="$ROOT/ops/hooks/$name"
  local dst="$HOOKS_DIR/$name"
  if [ ! -f "$src" ]; then
    echo "Missing hook source: $src" >&2
    exit 1
  fi
  cp "$src" "$dst"
  chmod +x "$dst"
  echo "Installed hook: $name"
}

install_one pre-push

echo "Done. Hooks are local to this clone."
