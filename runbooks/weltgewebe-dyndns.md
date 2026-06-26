---
id: runbook-weltgewebe-dyndns
role: runbooks
status: active
canonicality: canonical
doc_type: runbook
title: Weltgewebe DynDNS auf Heimberry
summary: Reproduzierbarer Betrieb des INWX-DynDNS-Dienstes für die öffentliche Weltgewebe-Frontdoor
last_reviewed: 2026-06-25
depends_on:
  - constitution
  - naming
verifies_with:
  - scripts/tests/test_weltgewebe_ddns.py
  - scripts/tests/test_ddns_bundle.sh
---

# Weltgewebe DynDNS auf Heimberry

## Zweck und Ownership

Der Dienst hält die öffentlichen A-Records für `weltgewebe.net`,
`www.weltgewebe.net` und `api.weltgewebe.net` auf der aktuellen öffentlichen
IPv4-Adresse.

Die Rollen bleiben getrennt:

- Weltgewebe definiert Hostnamen und Anwendungsanforderungen.
- Heimserver besitzt Implementierung, systemd-Einheiten, Installation, Recovery
  und Betriebsprüfung.
- Heimberry führt den Dienst aus. Die öffentliche Frontdoor bleibt Edge-Caddy
  auf dem Heimserver.

## Sicherheitsgrenze

DynDNS öffnet selbst keinen Port. Die öffentliche Erreichbarkeit ist eine eng
begrenzte Ausnahme von der internen Standardarchitektur und gilt ausschließlich
für die dokumentierten Weltgewebe-Hostnamen über Edge-Caddy auf TCP 80/443.

Dadurch werden weder App-Container direkt veröffentlicht noch Admin-,
Datenbank- oder Diagnoseports freigegeben. Heimberry bleibt ohne eingehenden
Internetdienst, und `home.arpa` bleibt ausschließlich interne DNS-Wahrheit.

## Artefakte

| Repository | Installierter Pfad |
|---|---|
| `scripts/heimberry/weltgewebe_ddns.py` | `/usr/local/sbin/weltgewebe-ddns` |
| `ops/systemd/weltgewebe-ddns.service` | `/etc/systemd/system/weltgewebe-ddns.service` |
| `ops/systemd/weltgewebe-ddns.timer` | `/etc/systemd/system/weltgewebe-ddns.timer` |

Providerdaten liegen ausschließlich außerhalb von Git unter
`/etc/weltgewebe-ddns/`. Für jeden Host existiert eine eigene, nur für root
lesbare Datei mit dem Namen `<host>.password`, passend zur bestehenden
Heimberry-Runtime. Der Installer prüft nur Existenz, Eigentümer, Modus und
Nicht-Leerheit dieser Dateien; er liest keine Credential-Inhalte. Werte dürfen
nicht in Commits, Logs oder Abschlussberichte gelangen.

Review-Regel: Den Updater selbst nicht aus dem Repository heraus ausführen.
Ein echter Lauf liest die aktuelle WAN-IP und kann bei Drift Provider-Updates
auslösen. Für PR-Prüfungen werden ausschließlich Unit-Tests, Staging mit
`DESTDIR` und systemd-Syntaxprüfungen verwendet.

## Funktionsweise

Ein Lauf:

1. ermittelt die WAN-IPv4 unabhängig über IPify und OpenDNS,
2. verwirft private, reservierte, Loopback-, Link-Local- und CGNAT-Adressen,
3. bricht bei widersprüchlichen WAN-Quellen ohne Provider-Write ab,
4. fragt drei autoritative INWX-Nameserver für alle drei Hostnamen ab,
5. bricht bei DNS-Transport-, Timeout- oder Command-Fehlern fail-closed ab,
6. behandelt leere, aber erfolgreich abgefragte A-Record-Antworten als Drift,
7. schreibt nur für betroffene Hosts über den INWX-DynDNS-Endpunkt,
8. verifiziert anschließend den autoritativen Zustand,
9. schreibt einen atomaren Status unter `/var/lib/weltgewebe-ddns/state.json`,
10. protokolliert strukturierte JSON-Ereignisse in journald.

Ein Dateilock verhindert parallele Läufe. Der Timer startet alle fünf Minuten
mit Zufallsversatz und führt verpasste Läufe nach dem Boot nach.

## Installation

Voraussetzungen: Python 3, `dig`, ausgehendes HTTPS/DNS und die drei separat
provisionierten Providerdateien `weltgewebe.net.password`,
`www.weltgewebe.net.password` und `api.weltgewebe.net.password` mit Eigentümer
`root:root` und Modus `0600`.

Dateien installieren, ohne den laufenden Dienst zu verändern:

```bash
sudo scripts/heimberry/install_weltgewebe_ddns.sh
```

Der Standard-Installer installiert nur Dateien und legt das Konfigurations-
verzeichnis an. Er lädt systemd nicht neu, aktiviert keinen Timer und startet
keinen Dienst.

Nach Prüfung der extern provisionierten Dateien aktivieren:

```bash
sudo scripts/heimberry/install_weltgewebe_ddns.sh --activate
```

`--activate` lädt systemd neu, aktiviert den Timer und führt einen unmittelbaren
Lauf aus. Ohne diese Option wird kein Dienst gestartet.

## Read-only-Prüfung

```bash
sudo scripts/heimberry/install_weltgewebe_ddns.sh --check
```

`--check` ist eine deterministische Driftprüfung der installierten Dateien,
Modi und Eigentümer. Der Aktivierungszustand des Timers wird bewusst nicht
bewertet, damit eine nicht aktivierte Standardinstallation nicht als Drift gilt.

Separat, nur wenn der Dienst bereits explizit aktiviert wurde:

```bash
systemctl status weltgewebe-ddns.timer --no-pager
systemctl status weltgewebe-ddns.service --no-pager
journalctl -u weltgewebe-ddns.service -n 50 --no-pager -o short-iso
```

Staging ohne Live-Mutation:

```bash
tmp="$(mktemp -d)"
DESTDIR="$tmp/root" scripts/heimberry/install_weltgewebe_ddns.sh
DESTDIR="$tmp/root" scripts/heimberry/install_weltgewebe_ddns.sh --check
```

Autoritative Sicht:

```bash
for ns in ns.inwx.de ns2.inwx.de ns3.inwx.eu; do
  for host in weltgewebe.net www.weltgewebe.net api.weltgewebe.net; do
    dig +noall +comments +answer "@$ns" "$host" A
  done
done
```

Die WAN-IP ist Runtime-Zustand und wird nicht als kanonischer Wert ins
Repository geschrieben.

## Ereignisse

- `dyndns.no_change`: Alle neun Prüfungen entsprechen bereits der WAN-IP.
- `dyndns.update_succeeded`: Alle Nameserver bestätigen den Zielzustand.
- `dyndns.wan_consensus_failed`: WAN-Quellen fehlen oder widersprechen sich;
  kein Provider-Write.
- `dyndns.authoritative_dns_failed`: Autoritative DNS-Abfrage ist technisch
  fehlgeschlagen; kein Provider-Write.
- `dyndns.update_failed`: Transport oder Providerantwort ist fehlgeschlagen.
- `dyndns.verification_failed`: Der autoritative Zielzustand wurde nicht
  bestätigt.
- `dyndns.concurrent_run`: Ein vorheriger Lauf ist noch aktiv.

Das Verhalten ist fail-closed. DNS ist ein Telefonbuch; bei Zweifel trägt man
nicht vorsorglich irgendeine Nummer ein.

## Rollback

1. `sudo systemctl disable --now weltgewebe-ddns.timer`
2. Programm und Einheiten aus dem zuletzt freigegebenen Commit installieren.
3. `systemd-analyze verify` und `systemctl daemon-reload` ausführen.
4. Mit `--activate` reaktivieren und die autoritative Sicht prüfen.

Providerdateien werden beim Rollback nicht gelöscht oder überschrieben. Ein
Rollback auf statische IP-Werte in Git ist verboten.
