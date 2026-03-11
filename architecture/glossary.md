---
id: glossary
role: norm
status: canonical
last_reviewed: 2026-03-11
depends_on:
  - constitution
verifies_with:
---

# Glossary (Glossar)

This glossary defines canonical terms used across the Heimserver infrastructure to ensure semantic consistency, particularly for agents and operational governance.

## K

**Kanon (Canon)**
The definitive, documented truth of the infrastructure's intended or actual state, residing strictly in `architecture/` (Norm) or `runtime/` (Reality).

## D

**Drift**
The divergence between the observed runtime reality (e.g., actual open ports, running containers) and the normative architecture defined in the Canon. Identified via `preflight.sh`.

## E

**Edge**
The entry point from the public internet into the Heimserver, strictly managed by the Edge-Caddy gateway. It handles TLS termination and ingress.

## I

**Internal Only (Policy)**
A security boundary stipulating that application containers (e.g., Weltgewebe UI, API, NATS, DB) must not bind host ports. They communicate strictly over internal Docker networks.

## P

**Port-Ownership**
The exclusive assignment of host ports to specific services or roles (e.g., 8081 exclusively to `pihole-FTL`). Formally specified in `networking/port-matrix.md`.

## S

**Splitbrain**
A state where multiple conflicting sources of truth exist, usually caused by failing to synchronize runtime reality, documentation, and configuration files.

## P

**Preflight**
The primary suite of operational checks (`ops/checks/preflight.sh`) executed before and after actions to measure Drift and enforce the Port Matrix Guard.

## W

**Weltgewebe**
The application stack hosted on the Heimserver. It is strictly separated from the Heimserver's operational deployment configuration.

## H

**Heimserver**
The underlying host and operational configuration (this repository) serving as the Edge-Node for Weltgewebe and defining security, networking, and deployment bounds.
