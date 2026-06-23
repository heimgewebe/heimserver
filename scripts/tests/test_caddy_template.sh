#!/usr/bin/env bash
set -euo pipefail

TEMPLATE="edge/Caddyfile.template"
echo "== Testing $TEMPLATE =="

# 14.1 Syntax und Adaptierung
echo "[TEST] Syntax und Adaptierung"
ADAPTED_JSON="$(docker run --rm --network none -v "$PWD:/repo:ro" -w /repo caddy:2.8.4 caddy adapt --adapter caddyfile --config "$TEMPLATE" 2>/dev/null)"
echo "✅ Syntax is valid."

# Helper function to check strings in JSON
check_in_json() {
    local text="$1"
    local desc="$2"
    if echo "$ADAPTED_JSON" | grep -qF "$text"; then
        echo "✅ FOUND: $desc"
    else
        echo "❌ MISSING: $desc"
        exit 1
    fi
}

check_not_in_json() {
    local text="$1"
    local desc="$2"
    if echo "$ADAPTED_JSON" | grep -qF "$text"; then
        echo "❌ UNEXPECTED: $desc"
        exit 1
    else
        echo "✅ NOT FOUND: $desc"
    fi
}

# 14.2 Positive Hostverträge
check_in_json '"weltgewebe.net"' "Host: weltgewebe.net"
check_in_json '"www.weltgewebe.net"' "Host: www.weltgewebe.net"
check_in_json '"api.weltgewebe.net"' "Host: api.weltgewebe.net"

# 14.3 Webvertrag
check_in_json '"/local-basemap/*"' "Basemap route"
check_in_json '"/api/*"' "API route"
check_in_json '"/health/*"' "Health route"
check_in_json '"/_app/immutable/*"' "Immutable assets route"
check_in_json '"/_app/version.json"' "version.json route"
check_in_json '"X-Frame-Options"' "Security header"
check_in_json '"Cache-Control"' "Cache header"

# 14.4 API-Vertrag
# Check api upstream exists
check_in_json '"weltgewebe-api:8080"' "Upstream weltgewebe-api:8080"

# 14.5 Negative Hostverträge
check_not_in_json '"weltweb.net"' "Negative host weltweb.net"
check_not_in_json '"www.weltweb.net"' "Negative host www.weltweb.net"
check_not_in_json '"weltweberei.org"' "Negative host weltweberei.org"
check_not_in_json '"www.weltweberei.org"' "Negative host www.weltweberei.org"

# 14.6 Bestehende interne Hosts
check_in_json '"leitstand.heimgewebe.home.arpa"' "Internal host leitstand"
check_in_json '"weltgewebe.home.arpa"' "Internal host weltgewebe"
check_in_json '"api.weltgewebe.home.arpa"' "Internal host api.weltgewebe"

# 14.7 Keine fremden Reconciliation-Blöcke
check_not_in_json '"127.0.0.1:8081"' "Negative block 127.0.0.1:8081"
check_not_in_json '"heimserver.home.arpa"' "Negative host heimserver.home.arpa"

echo "== All template tests passed =="
