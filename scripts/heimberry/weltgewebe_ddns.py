#!/usr/bin/env python3
"""Keep the public Weltgewebe A records aligned with the WAN IPv4.

Provider authentication stays in root-owned curl configuration files outside
Git. This program never parses or logs their contents.
"""

from __future__ import annotations

import datetime as dt
import fcntl
import ipaddress
import json
import os
from pathlib import Path
import subprocess
import time
from typing import NoReturn
import urllib.error
import urllib.request

CONFIG_DIR = Path("/etc/weltgewebe-ddns")
STATE_DIR = Path("/var/lib/weltgewebe-ddns")
LOCK_FILE = Path("/run/weltgewebe-ddns/lock")

ENDPOINT = "https://dyndns.inwx.com/nic/update"
IPIFY_URL = "https://api.ipify.org"

HOSTS = (
    "weltgewebe.net",
    "www.weltgewebe.net",
    "api.weltgewebe.net",
)
NAMESERVERS = ("ns.inwx.de", "ns2.inwx.de", "ns3.inwx.eu")
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def log(event: str, **fields: object) -> None:
    payload = {
        "timestamp": dt.datetime.now(dt.timezone.utc).isoformat(),
        "event": event,
        **fields,
    }
    print(json.dumps(payload, sort_keys=True, ensure_ascii=False), flush=True)


def abort(exit_code: int, event: str, message: str, **fields: object) -> NoReturn:
    log(event, level="error", message=message, **fields)
    raise SystemExit(exit_code)


def validate_public_ipv4(value: str) -> str:
    try:
        address = ipaddress.ip_address(value)
    except ValueError:
        abort(3, "dyndns.wan_invalid", "WAN-Wert ist keine gültige IP-Adresse")
    if not isinstance(address, ipaddress.IPv4Address):
        abort(3, "dyndns.wan_invalid", "WAN-Wert ist keine IPv4-Adresse")
    if (
        not address.is_global
        or address.is_private
        or address.is_loopback
        or address.is_link_local
        or address.is_multicast
        or address.is_reserved
        or address in ipaddress.ip_network("100.64.0.0/10")
    ):
        abort(3, "dyndns.wan_invalid", "WAN-Adresse ist nicht öffentlich nutzbar")
    return str(address)


def determine_wan_ip() -> str:
    try:
        request = urllib.request.Request(IPIFY_URL, method="GET")
        with OPENER.open(request, timeout=10) as response:
            ipify = response.read(128).decode("utf-8", errors="replace").strip()
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        abort(
            3,
            "dyndns.wan_consensus_failed",
            "IPify-Abfrage fehlgeschlagen",
            error=type(error).__name__,
        )

    try:
        result = subprocess.run(
            [
                "/usr/bin/dig",
                "+time=3",
                "+tries=1",
                "+short",
                "A",
                "myip.opendns.com",
                "@resolver1.opendns.com",
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=8,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        abort(
            3,
            "dyndns.wan_consensus_failed",
            "OpenDNS-Abfrage fehlgeschlagen",
            error=type(error).__name__,
        )

    if result.returncode != 0:
        abort(
            3,
            "dyndns.wan_consensus_failed",
            "OpenDNS-Abfrage lieferte einen Fehlerstatus",
            returncode=result.returncode,
        )

    opendns = next(
        (line.strip() for line in result.stdout.splitlines() if line.strip()),
        "",
    )
    ipify = validate_public_ipv4(ipify)
    opendns = validate_public_ipv4(opendns)
    if ipify != opendns:
        abort(
            3,
            "dyndns.wan_consensus_failed",
            "WAN-IP-Quellen widersprechen sich",
        )
    log("dyndns.wan_consensus", wan_ipv4=ipify)
    return ipify


def query_a_record(nameserver: str, host: str) -> tuple[str, ...]:
    try:
        result = subprocess.run(
            [
                "/usr/bin/dig",
                "+time=3",
                "+tries=1",
                "+short",
                f"@{nameserver}",
                host,
                "A",
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=8,
        )
    except (OSError, subprocess.TimeoutExpired):
        return ()
    if result.returncode != 0:
        return ()

    addresses: set[str] = set()
    for line in result.stdout.splitlines():
        try:
            address = ipaddress.ip_address(line.strip())
        except ValueError:
            continue
        if isinstance(address, ipaddress.IPv4Address):
            addresses.add(str(address))
    return tuple(sorted(addresses))


def authoritative_state() -> dict[str, dict[str, tuple[str, ...]]]:
    return {
        nameserver: {
            host: query_a_record(nameserver, host)
            for host in HOSTS
        }
        for nameserver in NAMESERVERS
    }


def collect_mismatches(
    state: dict[str, dict[str, tuple[str, ...]]], expected: str
) -> list[dict[str, object]]:
    mismatches: list[dict[str, object]] = []
    for nameserver in NAMESERVERS:
        for host in HOSTS:
            values = state[nameserver][host]
            if values != (expected,):
                mismatches.append(
                    {
                        "nameserver": nameserver,
                        "host": host,
                        "values": list(values),
                    }
                )
    return mismatches


def hosts_requiring_update(mismatches: list[dict[str, object]]) -> tuple[str, ...]:
    affected = {str(item["host"]) for item in mismatches}
    return tuple(host for host in HOSTS if host in affected)


def update_host(host: str, wan_ip: str) -> str:
    provider_config = CONFIG_DIR / f"{host}.curl.conf"
    try:
        result = subprocess.run(
            [
                "/usr/bin/curl",
                "--silent",
                "--show-error",
                "--fail-with-body",
                "--max-time",
                "20",
                "--config",
                str(provider_config),
                "--get",
                "--data-urlencode",
                f"myip={wan_ip}",
                ENDPOINT,
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=25,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        abort(
            6,
            "dyndns.update_failed",
            "INWX-Update konnte nicht übertragen werden",
            host=host,
            error=type(error).__name__,
        )

    body = result.stdout.strip()
    status = body.split(maxsplit=1)[0].lower() if body else ""
    if result.returncode != 0 or status not in {"good", "nochg"}:
        abort(
            6,
            "dyndns.update_failed",
            "INWX-Update wurde nicht bestätigt",
            host=host,
            returncode=result.returncode,
            provider_status=status or "empty",
        )
    log("dyndns.host_updated", host=host, provider_status=status)
    return status


def write_state(*, wan_ip: str, result: str, provider_update: bool) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)
    payload = {
        "timestamp": dt.datetime.now(dt.timezone.utc).isoformat(),
        "wan_ipv4": wan_ip,
        "result": result,
        "provider_update": provider_update,
        "hosts": list(HOSTS),
    }
    temporary = STATE_DIR / ".state.json.tmp"
    target = STATE_DIR / "state.json"
    temporary.write_text(
        json.dumps(payload, sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
    )
    os.chmod(temporary, 0o600)
    os.replace(temporary, target)


def main() -> int:
    if not LOCK_FILE.parent.is_dir():
        abort(2, "dyndns.runtime_failed", "RuntimeDirectory fehlt")

    with LOCK_FILE.open("w", encoding="utf-8") as lock:
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            abort(9, "dyndns.concurrent_run", "Ein anderer Lauf ist bereits aktiv")

        wan_ip = determine_wan_ip()
        mismatches = collect_mismatches(authoritative_state(), wan_ip)
        if not mismatches:
            write_state(
                wan_ip=wan_ip,
                result="no_change",
                provider_update=False,
            )
            log("dyndns.no_change", wan_ipv4=wan_ip, checked_records=9)
            return 0

        update_hosts = hosts_requiring_update(mismatches)
        log(
            "dyndns.update_started",
            wan_ipv4=wan_ip,
            mismatch_count=len(mismatches),
            update_hosts=list(update_hosts),
        )
        for host in update_hosts:
            update_host(host, wan_ip)

        for attempt in range(1, 13):
            remaining = collect_mismatches(authoritative_state(), wan_ip)
            if not remaining:
                write_state(
                    wan_ip=wan_ip,
                    result="updated",
                    provider_update=True,
                )
                log(
                    "dyndns.update_succeeded",
                    wan_ipv4=wan_ip,
                    verification_attempt=attempt,
                    checked_records=9,
                )
                return 0
            log(
                "dyndns.verification_pending",
                wan_ipv4=wan_ip,
                verification_attempt=attempt,
                mismatch_count=len(remaining),
            )
            if attempt < 12:
                time.sleep(5)

        abort(
            7,
            "dyndns.verification_failed",
            "Autoritative INWX-Verifikation fehlgeschlagen",
            wan_ipv4=wan_ip,
        )


if __name__ == "__main__":
    raise SystemExit(main())
