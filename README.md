# heimserver

Kanonischer Kontext liegt in [`heimserver.constitution.md`](heimserver.constitution.md).

Primärer Einstieg für Agents: [`AGENTS.md`](AGENTS.md).

## Safety Checks (vor jedem Push)

Keine sensiblen Dateien getrackt?

    git ls-files | rg -n "(audit|server-facts|rules\\.v4|rules\\.v6|\\.env|wireguard|\\.key|\\.pem)" || echo "OK"
    git ls-files | grep -E "(audit|server-facts|rules\\.v4|rules\\.v6|\\.env|wireguard|\\.key|\\.pem)" || echo "OK"

Repo-Policy:
- Repo bleibt privat.
- Audit-Snapshots bleiben außerhalb des Repos (siehe heimserver.constitution.md).

## Quickstart

Hooks installieren (empfohlen):

    bash ops/install-hooks.sh

Preflight laufen lassen:

    bash ops/checks/preflight.sh

Secrets-Pfad initialisieren (Server):

    sudo bash ops/init-secrets-path.sh

Snapshot redacted kopieren (vor dem Teilen prüfen):

    bash ops/checks/redact_snapshot.sh /home/alex/server-facts/audit-snapshots/<ts>

## Repo-Intention

Dieses Repo ist ein Ops-Orakel:
- Doku ist nur dann wertvoll, wenn sie durch Checks **verifizierbar** ist.
- Templates statt Schlüssel: Komfort ohne Selbstsabotage.
