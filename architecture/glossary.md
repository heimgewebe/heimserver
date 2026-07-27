---
id: glossary
role: norm
status: deprecated
canonicality: explanatory
doc_type: reference
title: Historical Heimserver glossary
summary: Historical definitions from the retired Heimserver operating model
last_reviewed: 2026-07-27
depends_on:
  - constitution
verifies_with: []
---

# Historical Heimserver glossary

> **Historische Referenz — nicht ausführen.**

These definitions describe the former Heimserver operating model. They do not define current infrastructure, runtime health, deployment authority, or recovery authority. Current infrastructure truth belongs to `heimgewebe/infra` and to fresh runtime evidence from the active systems.

## Canon

The former repository used **Canon** for documented intended or observed Heimserver state in `architecture/` and `runtime/`. Those documents are now historical evidence rather than current authority.

## Drift

**Drift** described a difference between the former Heimserver architecture and an observed host state. The historical `ops/checks/preflight.sh` probe may now run only with explicit `ALLOW_HISTORICAL_HOST_READ=1` authorization and does not establish current system truth.

## Edge

**Edge** referred to the retired Heimserver ingress role previously implemented through Edge-Caddy. The repository no longer assigns that role to any host or service.

## Internal Only

**Internal Only** described the former container-network boundary under which application containers did not publish direct host ports. It remains useful only for interpreting historical configurations.

## Port ownership

**Port ownership** described the former exclusive assignment of host ports to services. Historical examples, including port 8081 and Pi-hole, do not reserve current ports or establish present service ownership.

## Splitbrain

**Splitbrain** described conflicting historical sources of intended and observed state. Current disagreements must be resolved in the active authoritative repositories and runtime surfaces, not in this retired repository.

## Preflight

**Preflight** referred to the former host-reading suite in `ops/checks/preflight.sh`. It is no longer a standard operational check and requires explicit historical-read authorization when used for bounded evidence work.

## Weltgewebe

**Weltgewebe** referred to the application stack formerly described as hosted through Heimserver infrastructure. This repository does not define its current hosting, routing, or deployment state.

## Heimserver

**Heimserver** referred to the retired host and this repository's former operational configuration. The host has no active role, exposure, fleet membership, or execution authority.
