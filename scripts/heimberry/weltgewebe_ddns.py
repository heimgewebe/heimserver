#!/usr/bin/env python3

from __future__ import annotations

import base64
import concurrent.futures
import datetime as dt
import fcntl
import ipaddress
import json
import os
import pathlib
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import NoReturn

if __name__ == "__main__":
    print(
        "Blocked: Heimserver is retired; public DNS mutation is unavailable "
        "from this repository",
        file=sys.stderr,
    )
    raise SystemExit(2)

# Historical implementation remains importable for isolated regression tests.
# Direct execution is unconditionally blocked above.

CONFIG_DIR = pathlib.Path("/etc/weltgewebe-ddns")
STATE_DIR = pathlib.Path("/var/lib/weltgewebe-ddns")
LOCK_FILE = pathlib.Path("/run/weltgewebe-ddns/lock")

ENDPOINT = "https://dyndns.inwx.com/nic/update"
IPIFY_URL = "https://api.ipify.org"

HOSTS = (
    "weltgewebe.net",
    "www.weltgewebe.net",
    "api.weltgewebe.net",
)

NAMESERVERS = (
    "ns.inwx.de",
    "ns2.inwx.de",
    "ns3.inwx.eu",
)

OPENER = urllib.request.build_opener(
    urllib.request.ProxyHandler({})
)


WAN_HTTP_TIMEOUT_SECONDS = 10
WAN_DNS_TIMEOUT_SECONDS = 8
AUTHORITATIVE_QUERY_TIMEOUT_SECONDS = 8
PROVIDER_UPDATE_TIMEOUT_SECONDS = 20
VERIFICATION_ATTEMPTS = 12
VERIFICATION_DELAY_SECONDS = 5
SERVICE_TIMEOUT_BUFFER_SECONDS = 60


def worst_case_runtime_seconds() -> int:
    authoritative_batches = 1 + VERIFICATION_ATTEMPTS
    return (
        WAN_HTTP_TIMEOUT_SECONDS
        + WAN_DNS_TIMEOUT_SECONDS
        + authoritative_batches * AUTHORITATIVE_QUERY_TIMEOUT_SECONDS
        + len(HOSTS) * PROVIDER_UPDATE_TIMEOUT_SECONDS
        + (VERIFICATION_ATTEMPTS - 1) * VERIFICATION_DELAY_SECONDS
    )


def log(event: str, **fields: object) -> None:
    payload = {
        "timestamp": dt.datetime.now(dt.timezone.utc).isoformat(),
        "event": event,
        **fields,
    }
    print(
        json.dumps(payload, sort_keys=True, ensure_ascii=False),
        flush=True,
    )


def abort(
    exit_code: int,
    event: str,
    message: str,
    **fields: object,
) -> NoReturn:
    log(
        event,
        level="error",
        message=message,
        **fields,
    )
    raise SystemExit(exit_code)


def http_text(
    url: str,
    *,
    headers: dict[str, str] | None = None,
    timeout: int = 10,
) -> str:
    request = urllib.request.Request(
        url,
        headers=headers or {},
        method="GET",
    )

    with OPENER.open(request, timeout=timeout) as response:
        return response.read(1024).decode(
            "utf-8",
            errors="replace",
        ).strip()


def validate_public_ipv4(value: str) -> str:
    try:
        address = ipaddress.ip_address(value)
    except ValueError:
        abort(
            3,
            "dyndns.wan_invalid",
            "WAN-Wert ist keine gültige IP-Adresse",
            value=value,
        )

    if not isinstance(address, ipaddress.IPv4Address):
        abort(
            3,
            "dyndns.wan_invalid",
            "WAN-Wert ist keine IPv4-Adresse",
            value=value,
        )

    cgnat = ipaddress.ip_network("100.64.0.0/10")

    if (
        not address.is_global
        or address.is_private
        or address.is_loopback
        or address.is_link_local
        or address.is_multicast
        or address.is_reserved
        or address in cgnat
    ):
        abort(
            3,
            "dyndns.wan_invalid",
            "WAN-Adresse ist nicht öffentlich nutzbar",
            value=value,
        )

    return str(address)


def determine_wan_ip() -> str:
    try:
        ipify = http_text(IPIFY_URL, timeout=WAN_HTTP_TIMEOUT_SECONDS)
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        abort(
            3,
            "dyndns.wan_consensus_failed",
            "IPIFY-Abfrage fehlgeschlagen",
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
            timeout=WAN_DNS_TIMEOUT_SECONDS,
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
        (
            line.strip()
            for line in result.stdout.splitlines()
            if line.strip()
        ),
        "",
    )

    ipify = validate_public_ipv4(ipify)
    opendns = validate_public_ipv4(opendns)

    if ipify != opendns:
        abort(
            3,
            "dyndns.wan_consensus_failed",
            "WAN-IP-Quellen widersprechen sich",
            ipify=ipify,
            opendns=opendns,
        )

    log(
        "dyndns.wan_consensus",
        wan_ipv4=ipify,
    )

    return ipify


def read_password(host: str) -> str:
    path = CONFIG_DIR / f"{host}.password"

    try:
        raw_password = path.read_text(encoding="utf-8")
    except OSError as error:
        abort(
            2,
            "dyndns.config_failed",
            "Passwortdatei konnte nicht gelesen werden",
            host=host,
            error=type(error).__name__,
        )

    if raw_password.endswith("\r\n"):
        password = raw_password[:-2]
    elif raw_password.endswith("\n"):
        password = raw_password[:-1]
    else:
        password = raw_password

    if not password:
        abort(
            2,
            "dyndns.config_failed",
            "Passwortdatei ist leer",
            host=host,
        )

    if "\n" in password or "\r" in password:
        abort(
            2,
            "dyndns.config_failed",
            "Passwortdatei enthält mehrere Zeilen",
            host=host,
        )

    return password


def parse_authoritative_answer(
    output: str,
    *,
    nameserver: str,
    host: str,
) -> tuple[str, ...]:
    status_match = re.search(
        r"\bstatus:\s*([A-Z0-9]+)\b",
        output,
        flags=re.IGNORECASE,
    )

    if status_match is None:
        abort(
            4,
            "dyndns.authoritative_dns_failed",
            "Autoritative DNS-Antwort enthält keinen auswertbaren Status",
            nameserver=nameserver,
            host=host,
            dns_status="missing",
        )

    dns_status = status_match.group(1).upper()

    if dns_status not in {"NOERROR", "NXDOMAIN"}:
        abort(
            4,
            "dyndns.authoritative_dns_failed",
            "Autoritative DNS-Antwort ist nicht sicher als Record-Zustand auswertbar",
            nameserver=nameserver,
            host=host,
            dns_status=dns_status,
        )

    addresses: set[str] = set()
    answer_lines = [
        line.strip()
        for line in output.splitlines()
        if line.strip() and not line.lstrip().startswith(";")
    ]

    if dns_status == "NXDOMAIN":
        if answer_lines:
            abort(
                4,
                "dyndns.authoritative_dns_failed",
                "NXDOMAIN-Antwort enthält unerwartete Answer-Records",
                nameserver=nameserver,
                host=host,
                dns_status=dns_status,
            )
        return ()

    for line in answer_lines:
        fields = line.split()
        if len(fields) < 5 or fields[-3].upper() != "IN" or fields[-2].upper() != "A":
            abort(
                4,
                "dyndns.authoritative_dns_failed",
                "Autoritative Answer-Section enthält einen unerwarteten Record",
                nameserver=nameserver,
                host=host,
                dns_status=dns_status,
            )

        try:
            address = ipaddress.ip_address(fields[-1])
        except ValueError:
            abort(
                4,
                "dyndns.authoritative_dns_failed",
                "Autoritativer A-Record enthält keine gültige IP-Adresse",
                nameserver=nameserver,
                host=host,
                dns_status=dns_status,
            )

        if not isinstance(address, ipaddress.IPv4Address):
            abort(
                4,
                "dyndns.authoritative_dns_failed",
                "Autoritativer A-Record enthält keine IPv4-Adresse",
                nameserver=nameserver,
                host=host,
                dns_status=dns_status,
            )

        addresses.add(str(address))

    return tuple(sorted(addresses))


def query_a_record(
    nameserver: str,
    host: str,
) -> tuple[str, ...]:
    try:
        result = subprocess.run(
            [
                "/usr/bin/dig",
                "+time=3",
                "+tries=1",
                "+noall",
                "+comments",
                "+answer",
                f"@{nameserver}",
                host,
                "A",
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=AUTHORITATIVE_QUERY_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        abort(
            4,
            "dyndns.authoritative_dns_failed",
            "Autoritative DNS-Abfrage überschritt das Zeitlimit",
            nameserver=nameserver,
            host=host,
        )
    except OSError as error:
        abort(
            4,
            "dyndns.authoritative_dns_failed",
            "Autoritative DNS-Abfrage konnte nicht gestartet werden",
            nameserver=nameserver,
            host=host,
            error=type(error).__name__,
        )

    if result.returncode != 0:
        abort(
            4,
            "dyndns.authoritative_dns_failed",
            "Autoritative DNS-Abfrage lieferte einen Fehlerstatus",
            nameserver=nameserver,
            host=host,
            returncode=result.returncode,
        )

    return parse_authoritative_answer(
        result.stdout,
        nameserver=nameserver,
        host=host,
    )


def authoritative_state() -> dict[str, dict[str, tuple[str, ...]]]:
    state: dict[str, dict[str, tuple[str, ...]]] = {
        nameserver: {} for nameserver in NAMESERVERS
    }
    pairs = [
        (nameserver, host)
        for nameserver in NAMESERVERS
        for host in HOSTS
    ]

    with concurrent.futures.ThreadPoolExecutor(max_workers=len(pairs)) as executor:
        futures = {
            executor.submit(query_a_record, nameserver, host): (nameserver, host)
            for nameserver, host in pairs
        }
        for future in concurrent.futures.as_completed(futures):
            nameserver, host = futures[future]
            state[nameserver][host] = future.result()

    return {
        nameserver: {host: state[nameserver][host] for host in HOSTS}
        for nameserver in NAMESERVERS
    }


def validate_credentials() -> None:
    for host in HOSTS:
        read_password(host)


def collect_mismatches(
    state: dict[str, dict[str, tuple[str, ...]]],
    expected: str,
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


def hosts_requiring_update(
    mismatches: list[dict[str, object]],
) -> tuple[str, ...]:
    affected = {str(item["host"]) for item in mismatches}
    return tuple(host for host in HOSTS if host in affected)


def update_host(host: str, wan_ip: str) -> str:
    password = read_password(host)

    credentials = base64.b64encode(
        f"{host}:{password}".encode("utf-8")
    ).decode("ascii")

    query = urllib.parse.urlencode(
        {"myip": wan_ip}
    )

    request = urllib.request.Request(
        f"{ENDPOINT}?{query}",
        headers={
            "Authorization": f"Basic {credentials}",
            "User-Agent": "weltgewebe-ddns/1.0",
        },
        method="GET",
    )

    try:
        with OPENER.open(request, timeout=PROVIDER_UPDATE_TIMEOUT_SECONDS) as response:
            body = response.read(1024).decode(
                "utf-8",
                errors="replace",
            ).strip()
    except urllib.error.HTTPError as error:
        status = "http_error"
        try:
            response_body = error.read(128).decode(
                "utf-8",
                errors="replace",
            ).strip()
            if response_body:
                status = response_body.split(maxsplit=1)[0][:32]
        except OSError:
            pass

        abort(
            6,
            "dyndns.update_failed",
            "INWX antwortete mit HTTP-Fehler",
            host=host,
            http_status=error.code,
            provider_status=status,
        )
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        abort(
            6,
            "dyndns.update_failed",
            "INWX-Update konnte nicht übertragen werden",
            host=host,
            error=type(error).__name__,
        )

    status = body.split(maxsplit=1)[0].lower() if body else ""

    if status not in {"good", "nochg"}:
        abort(
            6,
            "dyndns.update_failed",
            "Unerwartete INWX-Antwort",
            host=host,
            provider_status=status or "empty",
        )

    log(
        "dyndns.host_updated",
        host=host,
        provider_status=status,
    )

    return status


def write_state(
    *,
    wan_ip: str,
    result: str,
    provider_update: bool,
) -> None:
    STATE_DIR.mkdir(
        parents=True,
        exist_ok=True,
        mode=0o700,
    )

    payload = {
        "timestamp": dt.datetime.now(
            dt.timezone.utc
        ).isoformat(),
        "wan_ipv4": wan_ip,
        "result": result,
        "provider_update": provider_update,
        "hosts": list(HOSTS),
    }

    temporary = STATE_DIR / ".state.json.tmp"
    target = STATE_DIR / "state.json"

    temporary.write_text(
        json.dumps(
            payload,
            sort_keys=True,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    os.chmod(temporary, 0o600)
    os.replace(temporary, target)


def main() -> int:
    if not LOCK_FILE.parent.is_dir():
        abort(
            2,
            "dyndns.runtime_failed",
            "RuntimeDirectory fehlt",
        )

    with LOCK_FILE.open("w", encoding="utf-8") as lock:
        try:
            fcntl.flock(
                lock.fileno(),
                fcntl.LOCK_EX | fcntl.LOCK_NB,
            )
        except BlockingIOError:
            abort(
                9,
                "dyndns.concurrent_run",
                "Ein anderer Lauf ist bereits aktiv",
            )

        validate_credentials()
        wan_ip = determine_wan_ip()
        initial_state = authoritative_state()
        initial_mismatches = collect_mismatches(
            initial_state,
            wan_ip,
        )

        if not initial_mismatches:
            write_state(
                wan_ip=wan_ip,
                result="no_change",
                provider_update=False,
            )

            log(
                "dyndns.no_change",
                wan_ipv4=wan_ip,
                checked_records=9,
            )
            return 0

        log(
            "dyndns.update_started",
            wan_ipv4=wan_ip,
            mismatch_count=len(initial_mismatches),
            update_hosts=list(hosts_requiring_update(initial_mismatches)),
            mismatches=initial_mismatches,
        )

        for host in hosts_requiring_update(initial_mismatches):
            update_host(host, wan_ip)

        for attempt in range(1, VERIFICATION_ATTEMPTS + 1):
            state = authoritative_state()
            mismatches = collect_mismatches(
                state,
                wan_ip,
            )

            if not mismatches:
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
                mismatch_count=len(mismatches),
                mismatches=mismatches,
            )

            if attempt < VERIFICATION_ATTEMPTS:
                time.sleep(VERIFICATION_DELAY_SECONDS)

        abort(
            7,
            "dyndns.verification_failed",
            "Autoritative INWX-Verifikation fehlgeschlagen",
            wan_ipv4=wan_ip,
        )


if __name__ == "__main__":
    raise SystemExit(main())
