# Audit Snapshots

Dieses Verzeichnis enthält automatisch generierte Momentaufnahmen des Systemzustands (Container, Ports, Firewall, WireGuard).

**Policy:**
- Snapshots werden durch `.gitignore` standardmäßig **nicht** getrackt.
- Nur dieses `README.md` ist im Git.

**Sicherheits-Warnung:**
- Snapshots enthalten reale IPs, Subnetze und Konfigurationen.
- **Niemals unredacted teilen!** (Redaction erforderlich).
- WireGuard Private Keys werden durch `collect.sh` entfernt, aber Metadaten bleiben.
