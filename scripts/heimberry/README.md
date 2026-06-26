# Heimberry operations scripts

Repository-owned programs that are installed on Heimberry. Runtime values stay outside Git.

## Weltgewebe DynDNS

`weltgewebe_ddns.py` reconciles the three allowed public Weltgewebe A records only after two independent WAN sources agree and every authoritative INWX query completed successfully.

The existing Heimberry runtime contract is one root-owned password file per hostname under `/etc/weltgewebe-ddns/`:

- `weltgewebe.net.password`
- `www.weltgewebe.net.password`
- `api.weltgewebe.net.password`

The installer validates only credential metadata. It does not migrate the format, read the secret values, activate systemd, or start the updater unless `--activate` is explicit.
