# Heimberry scripts

`weltgewebe_ddns.py` is retained as a historical, fail-closed recovery artifact.
The public Weltgewebe runtime now lives on `wg-prod-1`; Heimberry must not update
its public A records.

`install_weltgewebe_ddns.sh --retire` disables the legacy timer while preserving
root-owned credentials. `--activate` is intentionally rejected. Both systemd
units require `/etc/weltgewebe-ddns/ENABLE_RETIRED_RUNTIME`, which is absent in
the supported retired state.
