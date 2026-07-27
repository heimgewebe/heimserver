---
id: runbooks-changelog
role: runbooks
status: archived
canonicality: explanatory
doc_type: reference
title: Historical Runbooks Changelog
summary: Historical record of superseded Heimserver runbook changes
last_reviewed: 2026-07-26
depends_on: []
verifies_with: []
---

> **Historische Referenz — nicht ausführen.** Dieses Dokument bewahrt einen früheren Stand. Es besitzt keine heutige Runtime-, Netzwerk-, Deployment-, Recovery- oder Infrastrukturautorität. Aktuelle Wahrheit liegt in `heimgewebe/infra` und frischen Runtime-Reads; eine Reaktivierung erfordert einen neuen Bureau-Task und einen dienstgebundenen Infra-Vertrag.

# CHANGELOG

## 2026-02-18

*   **RAM Upgrade:**
    *   Installed 2x 16GB DDR4-3200 SO-DIMM (Total: 32GB).
    *   `free -h` shows `Mem: 30Gi total` (expected for 32GB installed)
    *   `dmidecode` confirms 2x16GB @ 3200 MT/s, 1.2V
