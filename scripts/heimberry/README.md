# Heimberry scripts

`weltgewebe_ddns.py` is retained only as historical implementation evidence.
Direct execution is unconditionally blocked: this retired repository has no
authority to update public A records.

`install_weltgewebe_ddns.sh` likewise blocks its default install path,
`--retire`, and `--activate` before any file or service mutation. Only `--help`
and the read-only `--check` comparison remain available. The preserved systemd
units require `/etc/weltgewebe-ddns/ENABLE_RETIRED_RUNTIME`, which is absent in
the supported retired state.
