#!/usr/bin/env python3
import os
import sys
import re
from datetime import datetime

# Ensure we can import from scripts/lib
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from scripts.lib.docmeta import load_repo_index, parse_frontmatter, MANIFEST_PATH, _unquote

REVIEW_POLICY_PATH = 'manifest/review-policy.yaml'

def load_review_policy():
    """Simple parser for review policy yaml."""
    policy = {
        'default_review_cycle_days': 90,
        'mode': 'warn'
    }

    if os.path.exists(REVIEW_POLICY_PATH):
        with open(REVIEW_POLICY_PATH, 'r', encoding='utf-8') as f:
            for line in f:
                stripped = line.strip()
                if not stripped or stripped.startswith('#'):
                    continue

                if ':' in stripped:
                    key, val = stripped.split(':', 1)
                    key = key.strip()
                    val = val.strip()

                    if key == 'default_review_cycle_days':
                        try:
                            policy['default_review_cycle_days'] = int(val)
                        except ValueError:
                            pass
                    elif key == 'mode':
                        policy['mode'] = _unquote(val).lower()

    return policy

def main():
    print("Starting Document Review Age Check...")

    policy = load_review_policy()
    default_cycle = policy.get('default_review_cycle_days', 90)
    mode = policy.get('mode', 'warn')

    print(f"Policy: Cycle={default_cycle} days, Mode={mode}")

    try:
        manifest = load_repo_index(MANIFEST_PATH)
    except Exception as e:
        print(f"Error loading manifest: {e}")
        sys.exit(1)

    zones = manifest.get('zones', {})
    today = datetime.now()
    overdue_docs = []

    for zone_name, zone_data in zones.items():
        base_path = zone_data.get('path', '')
        docs = zone_data.get('canonical_docs', [])

        for doc in docs:
            filepath = os.path.join(base_path, doc)
            if not os.path.exists(filepath):
                continue

            fm = parse_frontmatter(filepath)
            if not fm:
                continue

            # Check for override in frontmatter (optional feature for future)
            cycle_days = default_cycle
            if 'review_cycle_days' in fm:
                try:
                    cycle_days = int(fm['review_cycle_days'])
                except ValueError:
                    # If invalid, stick to default
                    pass

            reviewed_str = fm.get('last_reviewed')
            if not reviewed_str:
                continue

            try:
                reviewed_date = datetime.strptime(str(reviewed_str), '%Y-%m-%d')
                age = (today - reviewed_date).days

                if age > cycle_days:
                    overdue_docs.append({
                        'doc': doc,
                        'path': filepath,
                        'age': age,
                        'limit': cycle_days
                    })
            except ValueError:
                continue

    if overdue_docs:
        print(f"\n⚠️  Found {len(overdue_docs)} overdue documents:")
        for item in overdue_docs:
            print(f" - {item['doc']} ({item['path']}): {item['age']} days (Limit: {item['limit']})")

        if mode == 'fail':
            print("\n❌ Policy violation. Failing check.")
            sys.exit(1)
        else:
            print("\n✅ Check passed (Warnings only).")
            sys.exit(0)
    else:
        print("\n✅ All documents are within review cycle.")
        sys.exit(0)

if __name__ == "__main__":
    main()
