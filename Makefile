.PHONY: help preflight snapshot redact hooks secrets validate-retired-reference validate-warnings validate-shell-tests validate-ddns-syntax validate-ddns-unit validate-ddns-bundle validate-ddns-systemd validate-ddns validate-generated generate diff-check validate

help:
	@echo "Targets:"
	@echo "  make preflight  - explicit historical host read (requires ALLOW_HISTORICAL_HOST_READ=1)"
	@echo "  make snapshot   - explicit historical host read (requires ALLOW_HISTORICAL_HOST_READ=1)"
	@echo "  make redact     - create redacted snapshot copy (review before sharing)"
	@echo "  make hooks      - install git hooks (local clone)"
	@echo "  make secrets    - blocked while Heimserver is retired"
	@echo "  make validate-ddns - run DynDNS syntax, unit, bundle and systemd checks"
	@echo "  make generate   - refresh generated repository artifacts"
	@echo "  make validate-generated - reject generated artifact drift"
	@echo "  make diff-check - run git diff --check"

preflight:
	@test "$(ALLOW_HISTORICAL_HOST_READ)" = "1" || (echo "Blocked: historical host read requires ALLOW_HISTORICAL_HOST_READ=1"; exit 2)
	bash ops/checks/preflight.sh

snapshot:
	@test "$(ALLOW_HISTORICAL_HOST_READ)" = "1" || (echo "Blocked: historical host read requires ALLOW_HISTORICAL_HOST_READ=1"; exit 2)
	bash ops/checks/snapshot.sh

redact:
	@echo "Usage: make redact SNAP=/path/to/snapshot"
	@test -n "$(SNAP)" || (echo "Missing SNAP=..."; exit 2)
	bash ops/checks/redact_snapshot.sh "$(SNAP)"

hooks:
	bash ops/install-hooks.sh

secrets:
	@echo "Blocked: Heimserver is retired; reintroduce this target only through a new Bureau task and service-bound infra contract"
	@exit 2

validate-retired-reference:
	python3 scripts/ci/check_retired_reference_contract.py

validate-warnings:
	-python3 scripts/ci/check-doc-review-age.py
	-bash scripts/ci/check-runbook-invariants.sh
	bash scripts/tests/test_preflight_mock.sh

validate-shell-tests:
	shellcheck ops/checks/preflight.sh
	shellcheck scripts/edge/check_admin_boundary.sh
	shellcheck scripts/edge/sync_caddyfile.sh
	shellcheck scripts/tests/test_edge_admin_boundary.sh
	shellcheck scripts/tests/test_edge_sync_runbook.sh
	shellcheck scripts/tests/test_edge_compose_contract.sh
	shellcheck scripts/tests/test_edge_contract_mutations.sh
	shellcheck scripts/tests/test_edge_redirect_target.sh
	shellcheck scripts/heimberry/install_weltgewebe_ddns.sh
	shellcheck scripts/tests/test_ddns_bundle.sh
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
		ulimit -c 0; \
		set +e; \
		systemd-analyze verify "$$tmp/systemd/weltgewebe-ddns.service" "$$tmp/systemd/weltgewebe-ddns.timer"; \
		status=$$?; \
		set -e; \
		if [ "$$status" -ne 0 ]; then \
			if [ "$${STRICT_SYSTEMD_ANALYZE:-0}" = "1" ] || [ "$$status" -ne 134 ]; then exit "$$status"; fi; \
			echo "WARN: host systemd-analyze crashed with status 134; CI remains strict" >&2; \
		fi; \
	else \
		if [ "$${STRICT_SYSTEMD_ANALYZE:-0}" = "1" ]; then echo "systemd-analyze missing" >&2; exit 1; fi; \
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

validate-generated: generate
	git diff --exit-code -- SYSTEM_MAP.md docs/_generated

diff-check:
	git diff --check

validate: validate-retired-reference validate-shell-tests validate-ddns validate-generated
	python3 scripts/ci/check_repo_index_consistency.py
	$(MAKE) validate-warnings
