.PHONY: help preflight snapshot redact hooks secrets

help:
	@echo "Targets:"
	@echo "  make preflight  - run ops checks"
	@echo "  make snapshot   - write audit snapshot outside git"
	@echo "  make redact     - create redacted snapshot copy (review before sharing)"
	@echo "  make hooks      - install git hooks (local clone)"
	@echo "  make secrets    - init /etc/heimserver/secrets (needs sudo)"

preflight:
	bash ops/checks/preflight.sh

snapshot:
	bash ops/checks/snapshot.sh

redact:
	@echo "Usage: make redact SNAP=/path/to/snapshot"
	@test -n "$(SNAP)" || (echo "Missing SNAP=..."; exit 2)
	bash ops/checks/redact_snapshot.sh "$(SNAP)"

hooks:
	bash ops/install-hooks.sh

secrets:
	sudo bash ops/init-secrets-path.sh
