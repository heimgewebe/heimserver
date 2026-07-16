---
id: runbook-weltgewebe-dyndns
role: runbooks
status: deprecated
canonicality: explanatory
doc_type: runbook
title: Weltgewebe DynDNS auf Heimberry
summary: Historischer, fail-closed stillgelegter INWX-DynDNS-Pfad; Produktion läuft auf wg-prod-1
last_reviewed: 2026-07-16
depends_on:
  - constitution
  - naming
verifies_with:
  - scripts/tests/test_weltgewebe_ddns.py
  - scripts/tests/test_ddns_bundle.sh
---

# Weltgewebe DynDNS auf Heimberry

## Status

Dieser Pfad ist **stillgelegt**. Die kanonische öffentliche Weltgewebe-Runtime
läuft auf dem VPS `wg-prod-1`; die drei öffentlichen A-Records zeigen auf dessen
statische IPv4. Heimberry darf diese Records nicht mehr mit seiner wechselnden
WAN-Adresse überschreiben.

Die Implementierung bleibt ausschließlich als historisches, testbares
Recovery-Artefakt erhalten. Der Timer muss deaktiviert bleiben. Service und Timer
benötigen zusätzlich die absichtlich fehlende Datei
`/etc/weltgewebe-ddns/ENABLE_RETIRED_RUNTIME`; dadurch kann ein versehentliches
Enable nicht wieder automatische Provider-Schreibvorgänge auslösen.

## Kontrollierte Stilllegung

```bash
sudo scripts/heimberry/install_weltgewebe_ddns.sh --retire
```

Der Befehl entfernt nur den Aktivierungsmarker, deaktiviert und stoppt den Timer
und bereinigt den historischen Fehlstatus. Programm, Units und root-lesbare
Providerdateien bleiben für Forensik und einen bewusst beschlossenen Rollback
erhalten.

Die frühere Option `--activate` wird fail-closed abgewiesen. Eine Reaktivierung
erfordert eine neue Architekturentscheidung, eine explizite DNS-Freigabe und
einen separaten Patch; das bloße Anlegen des Markers ist kein freigegebener
Betriebsweg.

## Read-only-Prüfung

```bash
sudo scripts/heimberry/install_weltgewebe_ddns.sh --check
systemctl is-enabled weltgewebe-ddns.timer   # erwartet: disabled
systemctl is-active weltgewebe-ddns.timer    # erwartet: inactive
```

Die Credentials dürfen weder gelesen noch gelöscht noch in Logs oder Berichte
kopiert werden. Öffentliche DNS- und HTTPS-Prüfungen erfolgen gegen den
kanonischen VPS-Pfad.

## Historische Funktionsgrenze

Der archivierte Client ermittelte die Heim-WAN-IP aus zwei Quellen, prüfte drei
autoritative INWX-Nameserver und schrieb nur für `weltgewebe.net`, `www` und
`api`. Diese Sicherheitsgrenzen bleiben getestet, begründen aber keine aktuelle
Ownership des DNS-Schreibpfads.

## Rollback

Kein operativer Standardrollback. Vor einer Reaktivierung müssen mindestens
VPS-Ausfall, neue Zielarchitektur, DNS-Ownership, Providerkonfiguration und
öffentliche Healthchecks neu beschlossen und belegt werden.
