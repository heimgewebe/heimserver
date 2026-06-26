.PHONY: help preflight snapshot redact hooks secrets validate-warnings validate-shell-tests validate

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

validate-warnings:
	-python3 scripts/ci/check-doc-review-age.py
	-bash scripts/ci/check-runbook-invariants.sh
	-bash scripts/tests/test_preflight_mock.sh

validate-shell-tests:
	shellcheck scripts/edge/check_admin_boundary.sh
	shellcheck scripts/edge/sync_caddyfile.sh
	shellcheck scripts/tests/test_edge_admin_boundary.sh
	shellcheck scripts/tests/test_edge_sync_runbook.sh
	shellcheck scripts/tests/test_edge_compose_contract.sh
	shellcheck scripts/tests/test_edge_contract_mutations.sh
	shellcheck scripts/tests/test_edge_redirect_target.sh
	python3 -m py_compile scripts/edge/validate_caddy_contract.py
	python3 -m py_compile scripts/edge/validate_compose_contract.py
	python3 -m py_compile scripts/tests/test_caddy_template.py
	python3 -m py_compile scripts/tests/edge_contract_json_mutations.py
	python3 -m py_compile scripts/tests/test_edge_noop_proof.py
	python3 -m py_compile scripts/tests/test_edge_ipv4_only.py
	python3 -m py_compile scripts/tests/test_edge_compose_stderr.py
	python3 scripts/tests/test_caddy_template.py
	bash scripts/tests/test_edge_admin_boundary.sh
	bash scripts/tests/test_edge_sync_runbook.sh
	bash scripts/tests/test_edge_compose_contract.sh
	python3 scripts/tests/test_edge_noop_proof.py
	python3 scripts/tests/test_edge_ipv4_only.py
	python3 scripts/tests/test_edge_compose_stderr.py
	bash scripts/tests/test_edge_contract_mutations.sh
	bash scripts/tests/test_edge_redirect_target.sh

validate: preflight validate-shell-tests
	python3 scripts/ci/check_repo_index_consistency.py
	$(MAKE) validate-warnings
