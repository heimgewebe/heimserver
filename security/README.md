# Security (Repo-Konventionen)

## Etymologie (Begriffsklärung)
„Security“ kommt über das Lateinische *securitas* („Sorglosigkeit, Sicherheit“),
gebildet aus *se-* („ohne“) + *cura* („Sorge“).
Ironie: In Ops bedeutet „Security“ meist „mit extra Sorgen, aber kontrolliert“.

## Secrets
- Private Keys und CA private keys werden **nicht** in Git versioniert.
- Kanonischer Pfad: `/etc/heimserver/secrets/`

## Templates
Alles in `security/templates/` ist **key-frei**.

## Checks
`ops/checks/preflight.sh` ist die operative Wahrheitsschicht.
