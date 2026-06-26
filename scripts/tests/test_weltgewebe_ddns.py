#!/usr/bin/env python3
from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import pathlib
import re
import stat
import subprocess
import tempfile
import unittest
from unittest import mock

REPO_ROOT = pathlib.Path(__file__).parents[2]
MODULE_PATH = REPO_ROOT / "scripts" / "heimberry" / "weltgewebe_ddns.py"
SERVICE_PATH = REPO_ROOT / "ops" / "systemd" / "weltgewebe-ddns.service"
SPEC = importlib.util.spec_from_file_location("weltgewebe_ddns", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
DDNS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DDNS)


class WeltgewebeDdnsTests(unittest.TestCase):
    def test_public_host_allowlist_is_exact(self) -> None:
        self.assertEqual(
            DDNS.HOSTS,
            (
                "weltgewebe.net",
                "www.weltgewebe.net",
                "api.weltgewebe.net",
            ),
        )

    def test_validate_public_ipv4_accepts_global_address(self) -> None:
        self.assertEqual(DDNS.validate_public_ipv4("1.1.1.1"), "1.1.1.1")

    def test_validate_public_ipv4_rejects_private_and_cgnat(self) -> None:
        for value in ("192.168.1.1", "100.64.0.1", "127.0.0.1", "::1"):
            with self.subTest(value=value), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(SystemExit) as raised:
                    DDNS.validate_public_ipv4(value)
                self.assertEqual(raised.exception.code, 3)

    def test_read_password_rejects_empty_and_multiline_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            config_dir = pathlib.Path(tmp)

            for content in ("", "secret\nsecond\n", "secret\n\n", "secret\r\n\r\n"):
                with self.subTest(content=content):
                    path = config_dir / "weltgewebe.net.password"
                    path.write_text(content, encoding="utf-8")

                    with (
                        mock.patch.object(DDNS, "CONFIG_DIR", config_dir),
                        contextlib.redirect_stdout(io.StringIO()),
                    ):
                        with self.assertRaises(SystemExit) as raised:
                            DDNS.read_password("weltgewebe.net")
                        self.assertEqual(raised.exception.code, 2)

    def test_read_password_accepts_single_line_with_optional_terminal_newline(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            config_dir = pathlib.Path(tmp)
            path = config_dir / "weltgewebe.net.password"

            for content in ("secret", "secret\n", "secret\r\n"):
                with self.subTest(content=content):
                    path.write_text(content, encoding="utf-8")
                    with mock.patch.object(DDNS, "CONFIG_DIR", config_dir):
                        self.assertEqual(DDNS.read_password("weltgewebe.net"), "secret")

    def test_validate_credentials_reads_all_exact_hosts(self) -> None:
        with mock.patch.object(DDNS, "read_password", return_value="secret") as read_password:
            DDNS.validate_credentials()

        self.assertEqual(
            [call.args for call in read_password.call_args_list],
            [(host,) for host in DDNS.HOSTS],
        )

    def test_service_timeout_covers_declared_worst_case_budget(self) -> None:
        service = SERVICE_PATH.read_text(encoding="utf-8")
        match = re.search(r"^TimeoutStartSec=(\d+)$", service, flags=re.MULTILINE)
        self.assertIsNotNone(match)
        timeout_seconds = int(match.group(1))
        self.assertGreaterEqual(
            timeout_seconds,
            DDNS.worst_case_runtime_seconds() + DDNS.SERVICE_TIMEOUT_BUFFER_SECONDS,
        )
        self.assertNotIn("ConditionFileIsExecutable=", service)
        self.assertNotIn("ConditionPathExists=", service)

    def test_authoritative_state_queries_every_pair(self) -> None:
        def answer(nameserver: str, host: str) -> tuple[str, ...]:
            self.assertIn(nameserver, DDNS.NAMESERVERS)
            self.assertIn(host, DDNS.HOSTS)
            return ("1.1.1.1",)

        with mock.patch.object(DDNS, "query_a_record", side_effect=answer) as query:
            state = DDNS.authoritative_state()

        self.assertEqual(
            state,
            {
                nameserver: {host: ("1.1.1.1",) for host in DDNS.HOSTS}
                for nameserver in DDNS.NAMESERVERS
            },
        )
        self.assertEqual(
            {call.args for call in query.call_args_list},
            {
                (nameserver, host)
                for nameserver in DDNS.NAMESERVERS
                for host in DDNS.HOSTS
            },
        )

    def test_collect_mismatches_reports_exact_nameserver_host_pair(self) -> None:
        expected = "1.1.1.1"
        state = {
            nameserver: {host: (expected,) for host in DDNS.HOSTS}
            for nameserver in DDNS.NAMESERVERS
        }
        state[DDNS.NAMESERVERS[1]][DDNS.HOSTS[2]] = ("9.9.9.9",)

        self.assertEqual(
            DDNS.collect_mismatches(state, expected),
            [{
                "nameserver": DDNS.NAMESERVERS[1],
                "host": DDNS.HOSTS[2],
                "values": ["9.9.9.9"],
            }],
        )

    def test_query_a_record_returns_ipv4_for_noerror_answer(self) -> None:
        completed = subprocess.CompletedProcess(
            args=["dig"],
            returncode=0,
            stdout=(
                ";; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1\n"
                "weltgewebe.net. 300 IN A 1.1.1.1\n"
            ),
            stderr="",
        )

        with mock.patch.object(DDNS.subprocess, "run", return_value=completed):
            self.assertEqual(
                DDNS.query_a_record("ns.inwx.de", "weltgewebe.net"),
                ("1.1.1.1",),
            )

    def test_query_a_record_returns_empty_tuple_for_successful_empty_answer(self) -> None:
        completed = subprocess.CompletedProcess(
            args=["dig"],
            returncode=0,
            stdout=";; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1\n",
            stderr="",
        )

        with mock.patch.object(DDNS.subprocess, "run", return_value=completed):
            self.assertEqual(
                DDNS.query_a_record("ns.inwx.de", "weltgewebe.net"),
                (),
            )

    def test_query_a_record_returns_empty_tuple_for_nxdomain(self) -> None:
        completed = subprocess.CompletedProcess(
            args=["dig"],
            returncode=0,
            stdout=";; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 1\n",
            stderr="",
        )

        with mock.patch.object(DDNS.subprocess, "run", return_value=completed):
            self.assertEqual(
                DDNS.query_a_record("ns.inwx.de", "weltgewebe.net"),
                (),
            )

    def test_query_a_record_aborts_on_unsafe_dns_status(self) -> None:
        for status in ("SERVFAIL", "REFUSED", "FORMERR", "NOTAUTH"):
            completed = subprocess.CompletedProcess(
                args=["dig"],
                returncode=0,
                stdout=f";; ->>HEADER<<- opcode: QUERY, status: {status}, id: 1\n",
                stderr="",
            )

            with (
                self.subTest(status=status),
                mock.patch.object(DDNS.subprocess, "run", return_value=completed),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                with self.assertRaises(SystemExit) as raised:
                    DDNS.query_a_record("ns.inwx.de", "weltgewebe.net")
                self.assertEqual(raised.exception.code, 4)

    def test_query_a_record_aborts_when_dns_status_is_missing(self) -> None:
        completed = subprocess.CompletedProcess(
            args=["dig"],
            returncode=0,
            stdout="",
            stderr="",
        )

        with (
            mock.patch.object(DDNS.subprocess, "run", return_value=completed),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            with self.assertRaises(SystemExit) as raised:
                DDNS.query_a_record("ns.inwx.de", "weltgewebe.net")
            self.assertEqual(raised.exception.code, 4)

    def test_query_a_record_aborts_on_unexpected_answer_record(self) -> None:
        completed = subprocess.CompletedProcess(
            args=["dig"],
            returncode=0,
            stdout=(
                ";; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1\n"
                "weltgewebe.net. 300 IN CNAME example.net.\n"
            ),
            stderr="",
        )

        with (
            mock.patch.object(DDNS.subprocess, "run", return_value=completed),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            with self.assertRaises(SystemExit) as raised:
                DDNS.query_a_record("ns.inwx.de", "weltgewebe.net")
            self.assertEqual(raised.exception.code, 4)

    def test_query_a_record_aborts_on_authoritative_command_error(self) -> None:
        completed = subprocess.CompletedProcess(
            args=["dig"],
            returncode=9,
            stdout="",
            stderr="network unreachable",
        )

        with (
            mock.patch.object(DDNS.subprocess, "run", return_value=completed),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            with self.assertRaises(SystemExit) as raised:
                DDNS.query_a_record("ns.inwx.de", "weltgewebe.net")
            self.assertEqual(raised.exception.code, 4)

    def test_query_a_record_aborts_on_authoritative_timeout(self) -> None:
        with (
            mock.patch.object(
                DDNS.subprocess,
                "run",
                side_effect=subprocess.TimeoutExpired(cmd=["dig"], timeout=8),
            ),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            with self.assertRaises(SystemExit) as raised:
                DDNS.query_a_record("ns.inwx.de", "weltgewebe.net")
            self.assertEqual(raised.exception.code, 4)

    def test_main_config_failure_stops_before_network_access(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            runtime_dir = pathlib.Path(tmp) / "run"
            runtime_dir.mkdir()

            with (
                mock.patch.object(DDNS, "LOCK_FILE", runtime_dir / "lock"),
                mock.patch.object(DDNS, "validate_credentials", side_effect=SystemExit(2)),
                mock.patch.object(DDNS, "determine_wan_ip") as determine_wan_ip,
                mock.patch.object(DDNS, "authoritative_state") as authoritative_state,
                mock.patch.object(DDNS, "update_host") as update_host,
                contextlib.redirect_stdout(io.StringIO()),
            ):
                with self.assertRaises(SystemExit) as raised:
                    DDNS.main()
                self.assertEqual(raised.exception.code, 2)

        determine_wan_ip.assert_not_called()
        authoritative_state.assert_not_called()
        update_host.assert_not_called()

    def test_main_no_change_does_not_call_provider(self) -> None:
        expected = "1.1.1.1"
        state = {
            nameserver: {host: (expected,) for host in DDNS.HOSTS}
            for nameserver in DDNS.NAMESERVERS
        }

        with tempfile.TemporaryDirectory() as tmp:
            runtime_dir = pathlib.Path(tmp) / "run"
            runtime_dir.mkdir()

            with (
                mock.patch.object(DDNS, "LOCK_FILE", runtime_dir / "lock"),
                mock.patch.object(DDNS, "validate_credentials"),
                mock.patch.object(DDNS, "determine_wan_ip", return_value=expected),
                mock.patch.object(DDNS, "authoritative_state", return_value=state),
                mock.patch.object(DDNS, "update_host") as update_host,
                mock.patch.object(DDNS, "write_state") as write_state,
                contextlib.redirect_stdout(io.StringIO()),
            ):
                self.assertEqual(DDNS.main(), 0)

        update_host.assert_not_called()
        write_state.assert_called_once_with(
            wan_ip=expected,
            result="no_change",
            provider_update=False,
        )

    def test_main_wan_failure_does_not_query_dns_or_provider(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            runtime_dir = pathlib.Path(tmp) / "run"
            runtime_dir.mkdir()

            with (
                mock.patch.object(DDNS, "LOCK_FILE", runtime_dir / "lock"),
                mock.patch.object(DDNS, "validate_credentials"),
                mock.patch.object(DDNS, "determine_wan_ip", side_effect=SystemExit(3)),
                mock.patch.object(DDNS, "authoritative_state") as authoritative_state,
                mock.patch.object(DDNS, "update_host") as update_host,
                contextlib.redirect_stdout(io.StringIO()),
            ):
                with self.assertRaises(SystemExit) as raised:
                    DDNS.main()
                self.assertEqual(raised.exception.code, 3)

        authoritative_state.assert_not_called()
        update_host.assert_not_called()

    def test_main_authoritative_failure_does_not_call_provider(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            runtime_dir = pathlib.Path(tmp) / "run"
            runtime_dir.mkdir()

            with (
                mock.patch.object(DDNS, "LOCK_FILE", runtime_dir / "lock"),
                mock.patch.object(DDNS, "validate_credentials"),
                mock.patch.object(DDNS, "determine_wan_ip", return_value="1.1.1.1"),
                mock.patch.object(DDNS, "authoritative_state", side_effect=SystemExit(4)),
                mock.patch.object(DDNS, "update_host") as update_host,
                contextlib.redirect_stdout(io.StringIO()),
            ):
                with self.assertRaises(SystemExit) as raised:
                    DDNS.main()
                self.assertEqual(raised.exception.code, 4)

        update_host.assert_not_called()

    def test_main_updates_all_hosts_and_verifies_authoritative_state(self) -> None:
        expected = "1.1.1.1"
        stale = {
            nameserver: {host: ("9.9.9.9",) for host in DDNS.HOSTS}
            for nameserver in DDNS.NAMESERVERS
        }
        current = {
            nameserver: {host: (expected,) for host in DDNS.HOSTS}
            for nameserver in DDNS.NAMESERVERS
        }

        with tempfile.TemporaryDirectory() as tmp:
            runtime_dir = pathlib.Path(tmp) / "run"
            runtime_dir.mkdir()

            with (
                mock.patch.object(DDNS, "LOCK_FILE", runtime_dir / "lock"),
                mock.patch.object(DDNS, "validate_credentials"),
                mock.patch.object(DDNS, "determine_wan_ip", return_value=expected),
                mock.patch.object(DDNS, "authoritative_state", side_effect=[stale, current]),
                mock.patch.object(DDNS, "update_host", return_value="good") as update_host,
                mock.patch.object(DDNS, "write_state") as write_state,
                contextlib.redirect_stdout(io.StringIO()),
            ):
                self.assertEqual(DDNS.main(), 0)

        self.assertEqual(
            [call.args for call in update_host.call_args_list],
            [(host, expected) for host in DDNS.HOSTS],
        )
        write_state.assert_called_once_with(
            wan_ip=expected,
            result="updated",
            provider_update=True,
        )

    def test_main_updates_only_hosts_with_successful_empty_authoritative_records(self) -> None:
        expected = "1.1.1.1"
        empty_host = DDNS.HOSTS[1]
        empty = {
            nameserver: {host: (expected,) for host in DDNS.HOSTS}
            for nameserver in DDNS.NAMESERVERS
        }
        current = {
            nameserver: {host: (expected,) for host in DDNS.HOSTS}
            for nameserver in DDNS.NAMESERVERS
        }
        for nameserver in DDNS.NAMESERVERS:
            empty[nameserver][empty_host] = ()

        with tempfile.TemporaryDirectory() as tmp:
            runtime_dir = pathlib.Path(tmp) / "run"
            runtime_dir.mkdir()

            with (
                mock.patch.object(DDNS, "LOCK_FILE", runtime_dir / "lock"),
                mock.patch.object(DDNS, "validate_credentials"),
                mock.patch.object(DDNS, "determine_wan_ip", return_value=expected),
                mock.patch.object(DDNS, "authoritative_state", side_effect=[empty, current]),
                mock.patch.object(DDNS, "update_host", return_value="good") as update_host,
                mock.patch.object(DDNS, "write_state") as write_state,
                contextlib.redirect_stdout(io.StringIO()),
            ):
                self.assertEqual(DDNS.main(), 0)

        update_host.assert_called_once_with(empty_host, expected)
        write_state.assert_called_once_with(
            wan_ip=expected,
            result="updated",
            provider_update=True,
        )

    def test_update_host_accepts_success_status_without_logging_secret(self) -> None:
        for provider_status in ("good", "nochg"):
            response = mock.MagicMock()
            response.read.return_value = f"{provider_status} 1.1.1.1".encode("utf-8")
            opener = mock.MagicMock()
            opener.open.return_value.__enter__.return_value = response
            output = io.StringIO()

            with (
                self.subTest(provider_status=provider_status),
                mock.patch.object(DDNS, "read_password", return_value="test-secret"),
                mock.patch.object(DDNS, "OPENER", opener),
                contextlib.redirect_stdout(output),
            ):
                self.assertEqual(
                    DDNS.update_host("weltgewebe.net", "1.1.1.1"),
                    provider_status,
                )

            self.assertNotIn("test-secret", output.getvalue())

    def test_update_host_rejects_unexpected_provider_status(self) -> None:
        for provider_status in ("badauth", "911", "", "unexpected"):
            response = mock.MagicMock()
            response.read.return_value = provider_status.encode("utf-8")
            opener = mock.MagicMock()
            opener.open.return_value.__enter__.return_value = response

            with (
                self.subTest(provider_status=provider_status),
                mock.patch.object(DDNS, "read_password", return_value="test-secret"),
                mock.patch.object(DDNS, "OPENER", opener),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                with self.assertRaises(SystemExit) as raised:
                    DDNS.update_host("weltgewebe.net", "1.1.1.1")
                self.assertEqual(raised.exception.code, 6)

    def test_update_host_rejects_transport_failure(self) -> None:
        opener = mock.MagicMock()
        opener.open.side_effect = DDNS.urllib.error.URLError("offline")

        with (
            mock.patch.object(DDNS, "read_password", return_value="test-secret"),
            mock.patch.object(DDNS, "OPENER", opener),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            with self.assertRaises(SystemExit) as raised:
                DDNS.update_host("weltgewebe.net", "1.1.1.1")
            self.assertEqual(raised.exception.code, 6)

    def test_write_state_is_atomic_and_private(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_dir = pathlib.Path(tmp) / "state"
            with mock.patch.object(DDNS, "STATE_DIR", state_dir):
                DDNS.write_state(
                    wan_ip="1.1.1.1",
                    result="no_change",
                    provider_update=False,
                )

            target = state_dir / "state.json"
            payload = json.loads(target.read_text(encoding="utf-8"))
            self.assertEqual(payload["wan_ipv4"], "1.1.1.1")
            self.assertEqual(payload["result"], "no_change")
            self.assertFalse(payload["provider_update"])
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
            self.assertFalse((state_dir / ".state.json.tmp").exists())


if __name__ == "__main__":
    unittest.main()
