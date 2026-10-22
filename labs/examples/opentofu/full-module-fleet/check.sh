#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
(cd case-1; tofu output -json) > outputs.json
python3 - <<'CHECK'
import json
x=json.load(open('outputs.json')); assert x; assert '-dev' in json.dumps(x)
print('Minimal output-only child module evaluated successfully.')
CHECK
for file in case-*/addresses.out; do
  case "$file" in case-1/*) continue ;; esac
  grep -q module.worker "$file"
done
