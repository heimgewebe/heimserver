#!/usr/bin/env python3
import os
import sys
import re
import tempfile
from datetime import datetime

# Ensure we can import from scripts/lib
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from scripts.lib.docmeta import load_repo_index, parse_frontmatter, MANIFEST_PATH, _unquote

REVIEW_POLICY_PATH = 'manifest/review-policy.yaml'
DEFAULT_CYCLE_DAYS = 90
DEFAULT_MODE = 'warn'

def load_review_policy(policy_path=REVIEW_POLICY_PATH):
    """Parse review-policy YAML (line-based). Returns (policy, warnings).
    Policy-Parser ist line-based subset; keine Inline-Comments, keine verschachtelten Strukturen."""
    policy = {
        'default_review_cycle_days': DEFAULT_CYCLE_DAYS,
        'mode': DEFAULT_MODE
    }
    warnings = 0

    if os.path.exists(policy_path):
        with open(policy_path, 'r', encoding='utf-8') as f:
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
                            policy['default_review_cycle_days'] = int(_unquote(val))
                        except ValueError:
                            print(f"Warning: Invalid '{key}' value '{val}', falling back to {DEFAULT_CYCLE_DAYS}.", file=sys.stderr)
                            policy['default_review_cycle_days'] = DEFAULT_CYCLE_DAYS
                            warnings += 1
                    elif key == 'mode':
                        mode_val = _unquote(val).lower()
                        if mode_val in ('warn', 'fail'):
                            policy['mode'] = mode_val
                        else:
                            print(f"Warning: Invalid '{key}' value '{val}', must be 'warn' or 'fail'. Falling back to '{DEFAULT_MODE}'.", file=sys.stderr)
                            policy['mode'] = DEFAULT_MODE
                            warnings += 1
                    else:
                        print(f"Warning: Unknown key '{key}' in policy file.", file=sys.stderr)
                        warnings += 1

    return policy, warnings

def main():
    print("Starting Document Review Age Check...")

    policy_path = os.environ.get('REVIEW_POLICY_PATH', REVIEW_POLICY_PATH)
    policy, warnings = load_review_policy(policy_path)
    default_cycle = policy.get('default_review_cycle_days', DEFAULT_CYCLE_DAYS)
    mode = policy.get('mode', DEFAULT_MODE)

    print(f"Policy: Cycle={default_cycle} days, Mode={mode}")
    print(f"Policy parsed with {warnings} warnings.")

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
                    cycle_days = int(_unquote(str(fm['review_cycle_days'])))
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
    # Selftest runs only when env var is set; CI uses normal path
    if os.environ.get('CHECK_SELFTEST') == '1':
        print("Running self-check...")
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', delete=False) as tf:
            temp_path = tf.name
            tf.write("default_review_cycle_days: 30\n")
            tf.write("default_review_cycle_days: nope\n")
            tf.write("mode: fail\n")
            tf.write("mode: wat\n")
            tf.write("unknown_key: true\n")

        try:
            policy, warnings = load_review_policy(temp_path)

            assert policy['default_review_cycle_days'] == DEFAULT_CYCLE_DAYS, f"Expected {DEFAULT_CYCLE_DAYS}, got {policy['default_review_cycle_days']}"
            assert policy['mode'] == DEFAULT_MODE, f"Expected '{DEFAULT_MODE}', got {policy['mode']}"
            assert warnings == 3, f"Expected exactly 3 warnings, got {warnings}"

            print("Self-check passed.")
        finally:
            try:
                os.remove(temp_path)
            except FileNotFoundError:
                pass

        sys.exit(0)

    main()
