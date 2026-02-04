# Optional: nicer UX than Makefile.
# Requires: `just`

default:
  @just --list

preflight:
  bash ops/checks/preflight.sh

snapshot:
  bash ops/checks/snapshot.sh

redact SNAP:
  bash ops/checks/redact_snapshot.sh "{{SNAP}}"

hooks:
  bash ops/install-hooks.sh

secrets:
  sudo bash ops/init-secrets-path.sh
