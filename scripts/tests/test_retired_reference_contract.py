#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import pathlib
import tempfile
import unittest
from unittest import mock

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
CHECKER_PATH = REPO_ROOT / "scripts" / "ci" / "check_retired_reference_contract.py"
SPEC = importlib.util.spec_from_file_location("retired_reference_contract", CHECKER_PATH)
assert SPEC is not None and SPEC.loader is not None
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


class RetiredReferenceContractTests(unittest.TestCase):
    def test_host_read_inventory_includes_every_canonical_collector(self) -> None:
        self.assertEqual(
            set(CHECKER.HOST_READ_SCRIPTS),
            {
                "ops/audit/collect.sh",
                "ops/checks/preflight.sh",
                "ops/checks/snapshot.sh",
            },
        )
        self.assertEqual(
            set(CHECKER.HOST_READ_OPERATIONS),
            set(CHECKER.HOST_READ_SCRIPTS),
        )

    def test_retained_mutator_inventory_matches_discovery(self) -> None:
        self.assertEqual(
            CHECKER._discover_retained_mutators(),
            set(CHECKER.BLOCKED_MUTATION_SCRIPTS),
        )
        self.assertEqual(
            set(CHECKER.BLOCKED_MUTATION_SCRIPTS),
            {
                "ops/init-secrets-path.sh",
                "scripts/edge/sync_caddyfile.sh",
                "scripts/heimberry/install_weltgewebe_ddns.sh",
                "scripts/heimberry/weltgewebe_ddns.py",
            },
        )

    def test_discovery_finds_new_service_mutator(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            script = root / "scripts" / "edge" / "restart.sh"
            script.parent.mkdir(parents=True)
            script.write_text(
                "#!/usr/bin/env bash\nsystemctl restart edge-caddy\n",
                encoding="utf-8",
            )
            script.chmod(0o755)

            with mock.patch.object(CHECKER, "ROOT", root):
                self.assertEqual(
                    CHECKER._discover_retained_mutators(),
                    {"scripts/edge/restart.sh"},
                )

    def test_discovery_does_not_block_read_only_checker(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            script = root / "scripts" / "edge" / "inspect.sh"
            script.parent.mkdir(parents=True)
            script.write_text(
                "#!/usr/bin/env bash\ndocker inspect edge-caddy\n",
                encoding="utf-8",
            )
            script.chmod(0o755)

            with mock.patch.object(CHECKER, "ROOT", root):
                self.assertEqual(CHECKER._discover_retained_mutators(), set())


if __name__ == "__main__":
    unittest.main()
