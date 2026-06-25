# Heimberry operations scripts

Repository-owned programs that are installed on Heimberry. Runtime values remain outside Git.

## Weltgewebe DynDNS

`weltgewebe_ddns.py` reconciles the three public Weltgewebe A records only after two independent WAN sources agree. It checks all authoritative INWX nameservers before and after a provider update.

Provider-specific curl configuration remains external to Git under `/etc/weltgewebe-ddns/`, one root-owned file per hostname. The program never parses or logs those files. Deployment and activation are intentionally not part of this preliminary slice until the repository-owned service contract and tests are present.
