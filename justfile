# Optional: nicer UX than Makefile.
# Requires: `just`

default:
  @just --list

preflight:
  make preflight

snapshot:
  make snapshot

redact SNAP:
  make redact SNAP="{{SNAP}}"

hooks:
  make hooks

secrets:
  make secrets
