#!/usr/bin/env bash
set -euo pipefail

# Redacts a snapshot directory into a shareable copy.
# Usage:
#   bash ops/checks/redact_snapshot.sh /path/to/snapshot [/path/to/out]
#
# Default out: <snapshot>-redacted

in="${1:-}"
if [[ -z "${in}" || ! -d "${in}" ]]; then
  echo "Usage: $0 /path/to/snapshot [/path/to/out]" >&2
  exit 2
fi

out="${2:-${in}-redacted}"
rm -rf "${out}"
mkdir -p "${out}"

cp -a "${in}/." "${out}/"

# Conservative redactions:
# - anything resembling private keys
# - wg private keys lines
# - obvious tokens/password strings (best-effort)
find "${out}" -type f -print0 2>/dev/null | while IFS= read -r -d '' f; do
  if file -b --mime-type "${f}" | grep -qE '^text/'; then
    sed -i \
      -e 's/^\s*PrivateKey\s*=.*$/PrivateKey = [REDACTED]/' \
      -e 's/-----BEGIN [A-Z ]*PRIVATE KEY-----/-----BEGIN [REDACTED PRIVATE KEY]-----/' \
      -e 's/-----END [A-Z ]*PRIVATE KEY-----/-----END [REDACTED PRIVATE KEY]-----/' \
      -e 's/(password|passwd|token|secret)\s*[:=]\s*[^[:space:]]+/\1: [REDACTED]/Ig' \
      "${f}" || true
  fi
done

echo "Redacted copy written:"
echo "  ${out}"
echo
echo "WARNING: best-effort redaction only."
echo "IPs/MACs/hostnames/paths may remain. Review before sharing."
