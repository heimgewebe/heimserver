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

validate-shell-tests:
	bash scripts/tests/test_preflight_mock.sh || true
	python3 scripts/tests/test_caddy_template.py
	bash scripts/tests/test_edge_sync_runbook.sh

validate: preflight validate-shell-tests
	python3 scripts/ci/check_repo_index_consistency.py
	python3 scripts/ci/check-doc-review-age.py || true
	bash scripts/ci/check-runbook-invariants.sh || true
