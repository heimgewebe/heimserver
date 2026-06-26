.PHONY: help preflight snapshot redact hooks secrets validate-warnings validate-shell-tests validate-ddns-syntax validate-ddns-unit validate-ddns-bundle validate-ddns-systemd validate-ddns generate diff-check validate

help:
	@echo "Targets:"
	@echo "  make preflight  - run ops checks"
	@echo "  make snapshot   - write audit snapshot outside git"
	@echo "  make redact     - create redacted snapshot copy (review before sharing)"
	@echo "  make hooks      - install git hooks (local clone)"
	@echo "  make secrets    - init /etc/heimserver/secrets (needs sudo)"
	@echo "  make validate-ddns - run DynDNS syntax, unit, bundle and systemd checks"
	@echo "  make generate   - refresh generated repository artifacts"
	@echo "  make diff-check - run git diff --check"

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
	shellcheck scripts/edge/sync_caddyfile.sh
	shellcheck scripts/tests/test_edge_sync_runbook.sh
	shellcheck scripts/tests/test_edge_compose_contract.sh
	shellcheck scripts/heimberry/install_weltgewebe_ddns.sh
	shellcheck scripts/tests/test_ddns_bundle.sh
	python3 scripts/tests/test_caddy_template.py
	bash scripts/tests/test_edge_sync_runbook.sh
	bash scripts/tests/test_edge_compose_contract.sh

validate-ddns-syntax:
	python3 -m py_compile scripts/heimberry/weltgewebe_ddns.py scripts/tests/test_weltgewebe_ddns.py
	bash -n scripts/heimberry/install_weltgewebe_ddns.sh
	bash -n scripts/tests/test_ddns_bundle.sh

validate-ddns-unit:
	python3 -m unittest scripts/tests/test_weltgewebe_ddns.py

validate-ddns-bundle:
	bash scripts/tests/test_ddns_bundle.sh

validate-ddns-systemd:
	@if command -v systemd-analyze >/dev/null 2>&1; then \
		tmp="$$(mktemp -d)"; \
		trap 'rm -rf "$$tmp"' EXIT; \
		install -d "$$tmp/bin" "$$tmp/systemd"; \
		cp scripts/heimberry/weltgewebe_ddns.py "$$tmp/bin/weltgewebe-ddns"; \
		chmod 0755 "$$tmp/bin/weltgewebe-ddns"; \
		sed "s#ExecStart=/usr/local/sbin/weltgewebe-ddns#ExecStart=$$tmp/bin/weltgewebe-ddns#" ops/systemd/weltgewebe-ddns.service > "$$tmp/systemd/weltgewebe-ddns.service"; \
		cp ops/systemd/weltgewebe-ddns.timer "$$tmp/systemd/weltgewebe-ddns.timer"; \
		systemd-analyze verify "$$tmp/systemd/weltgewebe-ddns.service" "$$tmp/systemd/weltgewebe-ddns.timer"; \
	else \
		echo "SKIP: systemd-analyze not available"; \
	fi

validate-ddns: validate-ddns-syntax validate-ddns-unit validate-ddns-bundle validate-ddns-systemd

generate:
	python3 scripts/generate-relations.py
	python3 scripts/generate-system-map.py
	python3 scripts/docmeta/generate-architecture-drift.py
	python3 scripts/docmeta/generate-doc-coverage.py
	python3 scripts/docmeta/generate-knowledge-gaps.py
	python3 scripts/docmeta/generate-agent-readiness.py

diff-check:
	git diff --check

validate: preflight validate-shell-tests validate-ddns
	python3 scripts/ci/check_repo_index_consistency.py
	$(MAKE) validate-warnings
