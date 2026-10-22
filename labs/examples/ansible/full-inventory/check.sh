#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
python3 - <<'CHECK'
import json
x=json.load(open('inventory-6.yaml.json'))
assert set(x['web']['hosts'])=={'web1','web2'}
assert x['production']['children']==['web']
print('Host grouping and nested selection verified; no connection to documentation IP addresses was attempted.')
CHECK
grep -q 'failed=0' result.log
